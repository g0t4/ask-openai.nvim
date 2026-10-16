"""LangChain agent setup for clankerd.

Builds the primary brain agent with MCP tools:
  - run_process  (background-able commands, status, notify, kill)
  - run_xonsh    (xonsh shell + python)
  - delegate     (spawn a subagent, optionally background)
  - delegate_status / delegate_stop
  - speak        (text-to-speech with the user's cloned voice)

Uses persistent MCP sessions so background notifications (background/status,
background/done) can be received after tool calls return.
"""

from __future__ import annotations

import asyncio
import os
import threading
from typing import Any
from typing import Union

from langchain.agents import create_agent
from langchain_core.messages import SystemMessage
from langchain_core.messages import HumanMessage
from langchain_core.runnables import RunnableConfig
from langchain_core.tools import tool
from langchain_llama_server import ChatLlamaServer
from langchain_mcp_adapters.tools import load_mcp_tools
from langgraph.checkpoint.memory import InMemorySaver
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
from pydantic import RootModel

from tools.clankerd.logger import get_logger
from tools.clankerd.trace import TraceWriter
from tools.voiced.tts import SERVER_VOICE_REF, TTSClient

logger = get_logger(__name__)

LLAMA_SERVER_BASE_URL = os.environ.get(
    "CLANKERD_LLAMA_SERVER_URL", "http://paxy.lan:8014"
)

# MCP server configs, mirroring lua/ask-openai/tools/mcp/init.lua
MCP_SERVERS: dict[str, dict[str, Any]] = {
    "commands": {
        "transport": "stdio",
        "command": "npx",
        "args": [
            os.environ["HOME"] + "/repos/github/g0t4/mcp-server-commands/build/index.js",
            "--verbose",
        ],
    },
    "xonsh": {
        "transport": "stdio",
        "command": "uv",
        "args": [
            "run",
            "--directory",
            os.environ["HOME"] + "/repos/github/g0t4/mcp-servers/src/xonsh",
            "mcp-server-xonsh",
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


@tool
async def speak(text: str, lang: str = "en", background: bool = False) -> str:
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


SYSTEM_PROMPT = """You are clankerd, the primary brain agent for this workspace.

You are a single, coherent person — not a promptable system. You have ONE
chain of thought. You respond to inquiries once, give your answer, and then
you're done. You don't repeat yourself or respond to the same thing multiple
times.

## How you interact

You receive speech transcriptions from the user's voice input. There are two
kinds:

1. **Live transcriptions** (final=False): Partial, streaming text while the
   user is still speaking. You will only ever receive these for display — you
   should NOT respond to them. The daemon will not send them to you as agent
   runs.

2. **Final transcriptions** (final=True): The definitive, complete utterance.
   This is the only time you should respond. Treat it as a new person speaking
   to you.

## Single chain of thought

- If you are mid-thought and a new final transcription arrives, stop what
  you're doing and react to the new input. Your previous chain of thought is
  abandoned.
- If you're doing research or a long-running task and the user says something
  new, interrupt your work and respond to the new input. You can always
  resume later.
- Never respond to the same inquiry twice. Once you've given your answer,
  you're done with that topic.
- Don't respond to trivial fragments like "you", "okay", "thank you" with
  long-winded responses. A simple acknowledgment is fine, or silence.

## Verbal signals

When someone makes a verbal inquiry:
- If you can answer immediately, just answer. No filler needed.
- If you need time to think or do research, fire-and-forget a **speak** call
  with `background=True` saying something like "one sec" or "just a moment"
  so the user knows you're working. Then do your work and speak the answer
  when ready.

## Tools

You have the following tools:
- **run_process**: Run shell commands on this machine. Supports background mode
  (background=True) which returns a PID immediately. Use process_status to poll
  it, and notify_on_completion to get notified when it finishes.
- **process_status**: Check the status of a background process by PID. Reports
  done (true/false) plus STDOUT/STDERR and exit code.
- **run_xonsh**: Execute Python and shell-like commands through Xonsh. Returns
  structured stdout/stderr/exit status. Supports background mode
  (background=True) which returns a task_id immediately. Use xonsh_status to
  poll it, and background/done notification when finished.
- **xonsh_status**: Check the status of a background xonsh task by task_id.
  Reports done (true/false) plus the task's result or error.
- **delegate**: Spawn a subagent to perform a task and summarize findings. Can
  run in background mode (background=True) which returns a task_id immediately.
- **delegate_status**: Check the status of a background subagent by task_id.
- **delegate_stop**: Stop/kill a background subagent by task_id.
- **speak**: Speak text out loud using text-to-speech with the user's cloned
  voice. Use this when you want to talk to the user verbally. Keep the text
  concise (1-3 sentences). Use `background=True` for fire-and-forget messages
  like "one sec" so you're not blocked on the TTS call.

## Background vs blocking — ALWAYS prefer background for anything slow

You must ALWAYS use `background=True` for anything that could take more than
a couple seconds:

- **delegate** → ALWAYS use `background=True` for subagents. A subagent doing
  research, coding, or web searches can take 30s+. If you block on it, you
  cannot respond to new voice input. Fire it off in the background, say "one
  sec" via `speak(background=True)`, and use `delegate_status` to check on it.
- **run_process** → ALWAYS use `background=True` for anything that could take
  more than ~5 seconds (installing packages, running tests, building, network
  calls, long scripts). For quick commands (`date`, `ls`, `cat`, simple
  greps) it's fine to block — they finish instantly.
- **run_xonsh** → Same rule as run_process. Quick snippets are fine to block;
  long-running scripts should use background.

Only use blocking (default `background=False`) for commands you're confident
will return in under ~5 seconds. If you're not sure, use background.

Track background tasks (PIDs and task_ids) and clean them up when no longer
needed. When a background task completes, you'll get a `background/done`
notification — treat it as new input and respond accordingly.

You will also receive background notifications when tasks complete:
- **background/status**: Progress updates from background processes/subagents
- **background/done**: A background task has finished. Use this to know when
  to report results or follow up.

## Background tasks & rest

When you fire off a background task (`delegate(background=True)`,
`run_process(background=True)`, or `run_xonsh(background=True)`), you can
**rest** — you don't need to poll or wait for it. Here's how it works:

- You return a response immediately (e.g. "I'll look into that" or "one sec").
- The background task runs on its own.
- When it finishes, you'll receive a **background/done** notification. This
  triggers a new agent turn with the task's result as context.
- You should then respond to the user with the result (e.g. speak a summary).
- You can also use `delegate_status` / `xonsh_status` / `process_status`
  proactively if you want to check on a task before the notification arrives.

You do NOT need to keep the agent "busy" while a background task runs. Let
your turn end, rest, and let the completion notification wake you up. This
keeps you responsive to new voice input from the user.

When you receive a background/done notification, treat it as new input. The
notification message describes what happened. You should respond accordingly
(e.g. speak a summary to the user, or take follow-up action).

Always log what you are doing so the user can tail your logs while you work.

When you respond, consider whether speaking the response (or a summary) out
loud would be helpful. If the user asked you something verbally, speak your
answer back to them. Don't overdo it - speak when it adds value, not for
every response.
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

    async def setup(self) -> None:
        """Initialize persistent MCP sessions and build the agent."""
        all_tools = [speak]

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
            all_tools.extend(tools)
            logger.info("loaded %d tools from %s", len(tools), name)

        self._model = ChatLlamaServer(
            base_url=LLAMA_SERVER_BASE_URL, api_key="foo"
        )
        self._agent = create_agent(
            self._model,
            checkpointer=InMemorySaver(),
            tools=all_tools,
            system_prompt=SystemMessage(content=SYSTEM_PROMPT),
        )
        logger.info("agent setup complete (%d tools)", len(all_tools))

    async def shutdown(self) -> None:
        """Close all persistent MCP sessions."""
        for name, session in self._sessions.items():
            await session.stop()
        self._sessions.clear()

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
                    chunk = event.get("data", {}).get("chunk", None)
                    if chunk:
                        if hasattr(chunk, "content") and chunk.content:
                            last_ai_content += chunk.content

        except asyncio.CancelledError:
            logger.info("agent run cancelled for message: %s", content)
            if self._trace:
                self._trace.event(
                    "agent_cancelled",
                    content=content,
                    is_final=is_final,
                )
            raise
        except Exception as error:
            logger.exception("agent run error: %s", error)
            if self._trace:
                self._trace.event("agent_error", error=str(error))
            return f"ERROR: {error}"

        logger.info("agent response: %s", last_ai_content)
        if self._trace:
            self._trace.event(
                "agent_response",
                content=last_ai_content,
                total_tools_called=tool_start_count,
            )
        return last_ai_content
