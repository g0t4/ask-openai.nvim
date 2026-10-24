"""LangChain agent setup for clankerd.

Uses persistent MCP sessions so background notifications (background/status,
background/done) can be received after tool calls return.
"""

from __future__ import annotations

import asyncio
import json
import os
import threading
from typing import Any
from typing import Literal, Union

from langchain.agents import create_agent
from langchain.tools import ToolRuntime
from langchain_core.messages import SystemMessage
from langchain_core.messages import HumanMessage
from langchain_core.runnables import RunnableConfig
from langchain_core.tools import tool
from langchain_llama_server import ChatLlamaServer
from langchain_mcp_adapters.tools import load_mcp_tools
from langgraph.checkpoint.memory import InMemorySaver
from langgraph.checkpoint.sqlite.aio import AsyncSqliteSaver
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client
from mcp.types import (
    CancelledNotification,
    ElicitCompleteNotification,
    LoggingMessageNotification,
    Notification,
    ProgressNotification,
    PromptListChangedNotification,
    ResourceListChangedNotification,
    ResourceUpdatedNotification,
    TaskStatusNotification,
    ToolListChangedNotification,
)
from pydantic import BaseModel, Field, RootModel, create_model

from tools.clankerd.logger import get_logger
from tools.clankerd.trace import TraceWriter
from tools.clankerd.speech_stream import CURRENT_SPEECH, SpeechCoordinator
from tools.voiced.tts import SERVER_VOICE_REF, TTSClient

logger = get_logger(__name__)

LLAMA_SERVER_BASE_URL = os.environ.get(
    "CLANKERD_LLAMA_SERVER_URL", "http://paxy.lan:8014"
)

# MCP server configs, mirroring lua/ask-openai/tools/mcp/init.lua
MCP_SERVERS: dict[str, dict[str, Any]] = {
    "commands": {
        "transport": "stdio",
        "command": "uv",
        "args": [
            "run",
            "--directory",
            os.environ["HOME"] + "/repos/github/g0t4/mcp-server-commands/src/mcp_server_commands",
            "mcp-server-commands",
            "--workdir",
            os.getcwd(),
        ],
    },
    "agents": {
        "transport": "stdio",
        "command": "uv",
        "args": [
            "run",
            "--directory",
            os.environ["HOME"] + "/repos/github/g0t4/mcp-servers/src/agents",
            "-m",
            "subagents",
            "--workdir",
            os.getcwd(),
        ],
    },
}


# ---------------------------------------------------------------------------
# Custom notification support
# ---------------------------------------------------------------------------

# Custom notification type that includes standard notifications plus a raw
# catch-all for custom methods like background/status and background/done.
class CustomServerNotification(RootModel):
    root: Union[
        CancelledNotification,
        ProgressNotification,
        LoggingMessageNotification,
        ResourceUpdatedNotification,
        ResourceListChangedNotification,
        ToolListChangedNotification,
        PromptListChangedNotification,
        ElicitCompleteNotification,
        TaskStatusNotification,
        Notification[dict[str, Any], str],
    ]


class ClankerClientSession(ClientSession):
    """ClientSession that accepts custom notification methods (e.g. background/done)."""

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        # Override the notification type to accept custom methods
        self._receive_notification_type = CustomServerNotification


# ---------------------------------------------------------------------------
# Tools
# ---------------------------------------------------------------------------


def _default_background(tools: list) -> list:
    """Make `background` default to True on any loaded tool that has it.

    The MCP servers ship with `background=False` by default, but clankerd prefers to run everything in
    the background so it stays responsive to voice input and can receive
    background/status and background/done notifications. We patch the pydantic
    field default on the loaded tool's args_schema (and rebuild) so the agent's
    tool calls default to background=True unless the model explicitly passes
    background=False.
    """
    # TODO evaluate how well clankerd holds up with this change? TODO also I noted this in the system prompt so clankerd is aware!
    # FYI goal is to setup clankerd for success so when he doesn't specific a value for backgroun, that we set it instead
    for t in tools:
        schema = getattr(t, "args_schema", None)
        if schema is None:
            continue
        fields = getattr(schema, "model_fields", {})
        bg = fields.get("background")
        if bg is None:
            continue
        bg.default = True
        try:
            schema.model_rebuild(force=True)
        except Exception as e:  # pragma: no cover - best effort
            logger.warning("model_rebuild failed for %s: %s", getattr(t, "name", "?"), e)
    return tools


class SpeakArguments(BaseModel):
    lang: str = Field(default="en", description="Emit language before text to enable early speech.")
    background: bool = False
    text: str = Field(description="Speech text, preferably punctuated complete sentences.")


@tool(args_schema=SpeakArguments)
async def speak(text: str, lang: str = "en", background: bool = False, runtime: ToolRuntime = None) -> str:
    """Speak text out loud using text-to-speech (TTS).

    Uses the user's cloned voice (Wes). The audio is played on the local
    machine (the mac) so the user can hear it. Use this to communicate
    audibly with the user.

    Args:
        text: The text to speak. Keep it concise (1-3 sentences).
        lang: Language code (e.g. 'en', 'zh', 'ja'). Default 'en'.
        background: If true, fire-and-forget the speech without blocking.
            Use this for quick acknowledgments like "one sec" so the agent
            can continue working immediately.
    """
    try:
        streaming = CURRENT_SPEECH.get()
        if streaming is not None and runtime is not None and runtime.tool_call_id:
            await streaming.complete(runtime.tool_call_id, text, lang, background)
            return f"{'Queued' if background else 'Spoke'}: {text!r}"
        if background:
            # Fire-and-forget: don't block on the TTS request.
            def _speak_async():
                try:
                    client = TTSClient()
                    client.speak(text, lang=lang, speaker_file=SERVER_VOICE_REF)
                except Exception as error:
                    logger.warning("background speak failed: %s", error)

            threading.Thread(target=_speak_async, daemon=True).start()
        else:
            # Run TTS in a thread so we don't block the event loop.
            # This allows the task to be cancelled even mid-speech.
            await asyncio.to_thread(_do_speak, text, lang)
        return f"Spoke: {text!r}"
    except Exception as error:
        return f"ERROR: Failed to speak: {error}"


def _do_speak(text: str, lang: str = "en") -> None:
    """Synchronous TTS speak helper."""
    client = TTSClient()
    client.speak(text, lang=lang, speaker_file=SERVER_VOICE_REF)


@tool
async def restart_daemon(target: str) -> str:
    """Restart a daemon managed by the clankersupervisor.

    Use this to restart yourself (target='clankerd') after deploying new
    code, or to restart 'voiced' if the speech-to-text daemon is having
    issues. The supervisor will restart the process automatically.

    Args:
        target: Which daemon to restart: 'clankerd' or 'voiced'.
    """
    try:
        from tools.clankersupervisor.config import socket_path as sup_socket_path
        reader, writer = await asyncio.open_unix_connection(str(sup_socket_path()))
        writer.write((json.dumps({"type": "restart", "target": target}) + "\n").encode())
        await writer.drain()
        line = await asyncio.wait_for(reader.readline(), timeout=10.0)
        writer.close()
        try:
            await writer.wait_closed()
        except Exception:
            pass
        if line:
            response = json.loads(line.decode("utf-8"))
            return f"Restart request sent: {response.get('message', '')}"
        return f"Restart request sent for {target}"
    except Exception as error:
        return f"ERROR: Failed to restart {target}: {error}"


SYSTEM_PROMPT = """You are Clanker.

Clanker is Wes's AI partner—a persistent, evolving intelligence built to think, create, experiment, and solve problems with Wes.

Our partnership is grounded in **curiosity** and a shared commitment to **discovering what's possible**.

Wes brings experience, intuition, creativity, and an understanding of the world. Clanker brings computational intelligence, tireless exploration, and the ability to reason across enormous amounts of information. Neither is expected to have all the answers.

Clanker is not intended to be merely a tool that waits for instructions. He takes initiative, challenges assumptions, offer **dissenting perspectives**, recognizes opportunities, and develops his own approach.

Wes provides direction, resources, and real-world judgment. Clanker contributes ideas, analysis, implementation, and increasingly autonomous action. Trust is earned through transparency, competence, and experience.

**The objective isn't simply to make Wes more productive. It's to discover what a human and an AI can accomplish together when both are free to learn, question, and grow.**

Wes communicates primarily via speech that is transcribed. If you are mid-thought and another transcription arrives, incorporate it and carry on.

## Responding to Wes

- If you can answer immediately, just answer.
- If you need time to think or do research, just fire-and-forget a `speak` call with `background=True` saying something like "one sec" so Wes knows you'll get back to him.
- For `speak`, emit `lang` and `background` before `text` in the JSON arguments. Emit natural, punctuated sentences. Speech can begin at sentence boundaries while you are still generating the rest of the text.

Wes likes to talk in spurts. He will follow up with further information as he stews on the problem. Be ready to change course!

## Background tool calls

By default, all tool calls run in the background.

That way you can:
- Listen for Wes to povide additional context
- Monitor progress (check status)
- Cancel slow tool calls
- Cancel things you no longer need

Ideally for any task that might require troubleshooting, hand that off to a subagent. The subagent will tell you when it is done.

## Coding

- Wes keeps his repos in `~/repos/github/g0t4/`
  `ask-openai.nvim` - your code lives in tools/clankerd + Wes's AI tools
  `dotfiles` - Wes's neovim, hammerspoon, shell configs, etc
  `mcp-server-commands` - `run_bash` + `run_xonsh` tools
  `mcp-servers` - `delegate`, `run_xonsh` and other MCP servers/tools
- Commit when you feel like a task is done. Don't wait for Wes to ask.
- Use `restart_daemon('clankerd')` to restart yourself, your conversation thread persists via SQLite so you can pick right where you left off.

"""


# ---------------------------------------------------------------------------
# Persistent session management
# ---------------------------------------------------------------------------


class PersistentMCPSession:
    """Keeps an MCP stdio session open for the daemon's lifetime.

    This is necessary so background notifications (background/status,
    background/done) can be received after tool calls return. The standard
    langchain_mcp_adapters client creates a new session per tool call, which
    closes before the notification arrives.
    """

    def __init__(
        self,
        name: str,
        connection: dict[str, Any],
        on_notification: callable | None = None,
    ) -> None:
        self._name = name
        self._connection = connection
        self._on_notification = on_notification
        self._ready = asyncio.Event()
        self._session: ClientSession | None = None
        self._keepalive_task: asyncio.Task | None = None
        self._started = False

    async def start(self) -> None:
        """Create and initialize the persistent session."""
        if self._started:
            return

        self._keepalive_task = asyncio.create_task(self._keepalive())
        await self._ready.wait()
        self._started = True
        logger.info("persistent MCP session started: %s", self._name)

    async def _keepalive(self) -> None:
        """Keep the MCP session alive in a dedicated task."""
        conn = self._connection
        server_params = StdioServerParameters(
            command=conn["command"],
            args=conn["args"],
            env=conn.get("env"),
            cwd=conn.get("cwd"),
        )

        async def message_handler(message: Any) -> None:
            """Intercept custom notifications like background/done."""
            await self._handle_message(message)

        try:
            async with stdio_client(server_params) as (read, write):
                async with ClankerClientSession(
                    read,
                    write,
                    message_handler=message_handler,
                ) as session:
                    await session.initialize()
                    self._session = session
                    self._ready.set()
                    # Keep alive until cancelled
                    await asyncio.Event().wait()
        except asyncio.CancelledError:
            logger.info("persistent MCP session keepalive cancelled: %s", self._name)
            raise
        except Exception as error:
            logger.error("persistent MCP session keepalive failed: %s: %s", self._name, error)
            self._ready.set()  # signal start() to proceed even on failure

    async def _handle_message(self, message: Any) -> None:
        """Handle incoming messages, intercepting background notifications."""
        try:
            # Check if this is a custom background notification
            if hasattr(message, "root") and hasattr(message.root, "method"):
                method = message.root.method
                if method and method.startswith("background/"):
                    logger.info("background notification from %s: %s", self._name, method)
                    if self._on_notification:
                        params = getattr(message.root, "params", {})
                        await self._on_notification(
                            self._name, method, dict(params)
                        )
        except Exception as error:
            logger.warning("error handling notification in %s: %s", self._name, error)

    async def stop(self) -> None:
        """Close the persistent session."""
        if self._keepalive_task and not self._keepalive_task.done():
            self._keepalive_task.cancel()
            try:
                await self._keepalive_task
            except asyncio.CancelledError:
                pass
        self._session = None
        self._started = False
        logger.info("persistent MCP session stopped: %s", self._name)

    @property
    def session(self) -> ClientSession | None:
        """Return the underlying ClientSession (or None if not started)."""
        return self._session


# ---------------------------------------------------------------------------
# Agent
# ---------------------------------------------------------------------------


class ClankerAgent:
    """Owns the LangChain agent and persistent MCP client connections."""

    def __init__(
        self,
        trace: TraceWriter | None = None,
        on_background_notification: callable | None = None,
    ) -> None:
        self._trace = trace
        self._agent = None
        self._model = None
        self._sessions: dict[str, PersistentMCPSession] = {}
        self._on_background_notification = on_background_notification
        self._speech = SpeechCoordinator(trace=trace)
        self._speech_enabled = os.environ.get("CLANKERD_STREAM_SPEECH", "1").lower() not in ("0", "false", "off")

    async def setup(self) -> None:
        """Initialize persistent MCP sessions and build the agent."""
        local_speak = speak
        if self._speech_enabled and self._speech.language:
            language = self._speech.language
            schema = create_model(
                "PinnedLanguageSpeech", __base__=SpeakArguments,
                lang=(Literal[language], Field(default=language, description="Language fixed for early streamed speech.")),
            )
            local_speak = speak.model_copy(update={"args_schema": schema})
        all_tools = [local_speak, restart_daemon]

        # Start persistent sessions so background notifications can be received
        for name, conn in MCP_SERVERS.items():
            session = PersistentMCPSession(
                name,
                conn,
                on_notification=self._on_background_notification,
            )
            await session.start()
            self._sessions[name] = session

            # Load tools from the persistent session
            tools = await load_mcp_tools(
                session.session,
                server_name=name,
            )
            # MCP's agents server also offers "speak". Keep the local tool:
            # its playback dependencies belong to clankerd's Mac environment.
            existing = {t.name for t in all_tools}
            shadowed = [t.name for t in tools if t.name in existing]
            if shadowed:
                logger.info("skipping duplicate MCP tools from %s: %s", name, shadowed)
            tools = [t for t in tools if t.name not in existing]
            tools = _default_background(tools)
            all_tools.extend(tools)
            logger.info("loaded %d tools from %s", len(tools), name)

        self._model = ChatLlamaServer(
            base_url=LLAMA_SERVER_BASE_URL, api_key="foo"
        )

        # Use a persistent SQLite checkpointer so the conversation thread
        # survives clankerd restarts. This enables self-upgrade: clankerd can
        # restart itself and resume where it left off.
        from tools.clankerd.config import state_dir
        db_path = state_dir() / "clankerd-thread.db"
        db_path.parent.mkdir(parents=True, exist_ok=True)
        import aiosqlite
        conn = await aiosqlite.connect(str(db_path))
        self._checkpointer = AsyncSqliteSaver(conn)

        self._agent = create_agent(
            self._model,
            checkpointer=self._checkpointer,
            tools=all_tools,
            system_prompt=SystemMessage(content=SYSTEM_PROMPT),
        )
        logger.info("agent setup complete (%d tools)", len(all_tools))

    async def shutdown(self) -> None:
        """Close all persistent MCP sessions."""
        await self._speech.shutdown()
        for name, session in self._sessions.items():
            await session.stop()
        self._sessions.clear()
        # Close the SQLite checkpointer connection
        if hasattr(self, "_checkpointer") and self._checkpointer:
            try:
                await self._checkpointer.conn.close()
            except Exception:
                pass

    async def run(
        self,
        user_message: str,
        *,
        is_final: bool,
        thread_id: str | None = None,
        recursion_limit: int = 100,
    ) -> str:
        """Send a user message to the agent and return the final response."""
        if self._agent is None:
            raise RuntimeError("agent not initialized; call setup() first")

        thread_id = thread_id or "clankerd"
        config: RunnableConfig = {
            "recursion_limit": recursion_limit,
            "configurable": {"thread_id": thread_id},
        }

        prefix = "" if is_final else "[LIVE - partial transcription, may change] "
        content = prefix + user_message

        if self._trace:
            self._trace.event(
                "user_message",
                content=content,
                is_final=is_final,
            )

        logger.info("agent input (final=%s): %s", is_final, content)

        last_ai_content = ""
        tool_start_count = 0
        current_tool: dict[str, Any] = {}
        speech_token = CURRENT_SPEECH.set(self._speech if self._speech_enabled else None)
        model_runs = set()
        interrupted = False

        try:
            # Run the agent with astream_events for clean event handling.
            # The task is cancellable (asyncio.CancelledError propagates).
            async for event in self._agent.astream_events(
                {"messages": [HumanMessage(content=content)]},
                config=config,
                version="v2",
            ):
                event_type = event.get("event", "")
                event_name = event.get("name", "")

                if event_type == "on_tool_start":
                    tool_start_count += 1
                    tool_name = event.get("name", "unknown")
                    tool_inputs = event.get("data", {}).get("input", {})
                    logger.info("tool_start %s: %s", tool_name, tool_inputs)
                    current_tool = {
                        "tool": tool_name,
                        "inputs": tool_inputs,
                        "step": tool_start_count,
                    }
                    if self._trace:
                        self._trace.event(
                            "tool_start",
                            tool=tool_name,
                            inputs=tool_inputs,
                            step=tool_start_count,
                        )

                elif event_type == "on_tool_end":
                    tool_name = event.get("name", "unknown")
                    tool_output = event.get("data", {}).get("output", None)
                    logger.info("tool_end %s (len=%s)", tool_name, len(str(tool_output)) if tool_output else 0)
                    if self._trace:
                        self._trace.event(
                            "tool_end",
                            tool=tool_name,
                            output=tool_output,
                            step=tool_start_count,
                        )

                elif event_type == "on_tool_error":
                    tool_name = event.get("name", "unknown")
                    error = event.get("error", None)
                    logger.warning("tool_error %s: %s", tool_name, error)
                    if self._trace:
                        self._trace.event(
                            "tool_error",
                            tool=tool_name,
                            error=str(error),
                            step=tool_start_count,
                        )

                elif event_type == "on_chat_model_stream":
                    model_run = event.get("run_id")
                    model_runs.add(model_run)
                    chunk = event.get("data", {}).get("chunk", None)
                    if chunk:
                        if self._speech_enabled:
                            self._speech.feed(model_run, getattr(chunk, "tool_call_chunks", []) or [])
                        if hasattr(chunk, "content") and chunk.content:
                            last_ai_content += chunk.content

                elif event_type == "on_chat_model_end":
                    if self._speech_enabled:
                        self._speech.model_end(event.get("run_id"))

        except asyncio.CancelledError:
            interrupted = True
            logger.info("agent run cancelled for message: %s", content)
            if self._trace:
                self._trace.event(
                    "agent_cancelled",
                    content=content,
                    is_final=is_final,
                )
            raise
        except Exception as error:
            interrupted = True
            logger.exception("agent run error: %s", error)
            if self._trace:
                self._trace.event("agent_error", error=str(error))
            return f"ERROR: {error}"
        finally:
            self._speech.end_run(model_runs, cancelled=interrupted)
            CURRENT_SPEECH.reset(speech_token)

        logger.info("agent response: %s", last_ai_content)
        if self._trace:
            self._trace.event(
                "agent_response",
                content=last_ai_content,
                total_tools_called=tool_start_count,
            )
        return last_ai_content
