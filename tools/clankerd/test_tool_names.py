"""A remote speak tool must never replace clankerd's local audio playback."""
from types import SimpleNamespace

import pytest

from tools.clankerd import agent


@pytest.mark.asyncio
async def test_setup_preserves_local_speak_over_mcp_collision(monkeypatch, tmp_path):
    monkeypatch.setenv("XDG_STATE_HOME", str(tmp_path))

    class Session:
        def __init__(self, name, connection, **kwargs):
            self.session = name

        async def start(self):
            pass

        async def stop(self):
            pass

    remote_speak = SimpleNamespace(name="speak")
    remote_delegate = SimpleNamespace(name="delegate")

    async def load_tools(session, **kwargs):
        return [remote_speak, remote_delegate] if session == "agents" else []

    monkeypatch.setattr(agent, "PersistentMCPSession", Session)
    monkeypatch.setattr(agent, "load_mcp_tools", load_tools)
    monkeypatch.setattr(agent, "ChatLlamaServer", lambda **kwargs: object())
    monkeypatch.setattr(agent, "create_agent", lambda *args, **kwargs: SimpleNamespace(tools=kwargs["tools"]))
    instance = agent.ClankerAgent()
    try:
        await instance.setup()
        by_name = {tool.name: tool for tool in instance._agent.tools}
        assert len(by_name) == len(instance._agent.tools)
        assert by_name["speak"] is agent.speak
        assert by_name["delegate"] is remote_delegate
    finally:
        await instance.shutdown()
