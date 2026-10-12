"""LangChain agent setup for clankerd.

Builds the primary brain agent with MCP tools:
  - run_process  (background-able commands, status, notify, kill)
  - run_xonsh    (xonsh shell + python)
  - delegate     (spawn a subagent, optionally background)
  - delegate_status / delegate_stop
"""

from __future__ import annotations

import asyncio
import os
from typing import Any

from langchain.agents import create_agent
from langchain_core.messages import SystemMessage
from langchain_core.messages import HumanMessage
from langchain_core.runnables import RunnableConfig
from langchain_llama_server import ChatLlamaServer
from langchain_mcp_adapters.client import MultiServerMCPClient
from langgraph.checkpoint.memory import InMemorySaver

from tools.clankerd.logger import get_logger
from tools.clankerd.trace import TraceWriter

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


SYSTEM_PROMPT = """You are clankerd, the primary brain agent for this workspace.

You receive speech transcriptions from the user's voice input. There are two
kinds of transcription events:

1. **Live transcriptions** (final=False): These are partial, streaming
   transcriptions that arrive while the user is still speaking. They may be
   incomplete or change as more words come in. You MAY act on these if you are
   confident about the intent, but be prepared to change course when the final
   transcription arrives.

2. **Final transcriptions** (final=True): These are the definitive, complete
   transcription of the user's utterance. When you receive one of these, you
   should:
   - Re-evaluate any work you started based on live transcriptions
   - If your interpretation was wrong, abort the wrong-direction work (e.g. kill
     background processes you no longer need, cancel subagents)
   - Proceed with the correct interpretation

You have the following tools:
- **run_process**: Run shell commands on this machine. Supports background mode
  (background=True) which returns a PID immediately. Use process_status to poll
  it, and notify_on_completion to get notified when it finishes. This is great
  for long-running work. To kill a background process, use `kill <pid>` via
  run_process or run_xonsh.
- **process_status**: Check the status of a background process by PID. Reports
  done (true/false) plus STDOUT/STDERR and exit code. Optionally wait for
  completion (wait=true with wait_timeout_ms).
- **run_xonsh**: Execute Python and shell-like commands through Xonsh. Returns
  structured stdout/stderr/exit status.
- **delegate**: Spawn a subagent to perform a task and summarize findings. Can
  run in background mode (background=True) which returns a task_id immediately.
  Use delegate_status to check completion, delegate_stop to kill it.
- **delegate_status**: Check the status of a background subagent by task_id.
  Returns done (boolean) + the subagent's last status message + final output.
- **delegate_stop**: Stop/kill a background subagent by task_id.

Use delegation for long-running or parallel work so you remain responsive to
new voice input. Track background tasks (PIDs and task_ids) and clean them up
when no longer needed.

Always log what you are doing so the user can tail your logs while you work.
"""


class ClankerAgent:
    """Owns the LangChain agent and MCP client connections."""

    def __init__(self, trace: TraceWriter | None = None) -> None:
        self._trace = trace
        self._agent = None
        self._client = None
        self._model = None

    async def setup(self) -> None:
        """Initialize MCP clients and build the agent."""
        self._client = MultiServerMCPClient(MCP_SERVERS)
        mcp_tools = await self._client.get_tools()
        self._model = ChatLlamaServer(
            base_url=LLAMA_SERVER_BASE_URL, api_key="foo"
        )
        self._agent = create_agent(
            self._model,
            checkpointer=InMemorySaver(),
            tools=mcp_tools,
            system_prompt=SystemMessage(content=SYSTEM_PROMPT),
        )
        logger.info("agent setup complete (%d tools)", len(mcp_tools))

    async def run(
        self,
        user_message: str,
        *,
        is_final: bool,
        thread_id: str | None = None,
        recursion_limit: int = 50,
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
