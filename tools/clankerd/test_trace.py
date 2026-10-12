"""Pytest tests for the clankerd trace writer."""

from __future__ import annotations

import json

from tools.clankerd.trace import TraceWriter


def test_trace_writer_appends_events():
    trace = TraceWriter(trace_id="test123")

    trace.event("user_message", content="hello", is_final=True)
    trace.event("tool_start", tool="run_process", inputs={"command_line": "ls"})
    trace.event("agent_response", content="done")

    lines = trace.path.read_text().strip().split("\n")
    assert len(lines) == 4  # trace_started + 3 events

    first = json.loads(lines[0])
    assert first["type"] == "trace_started"
    assert first["trace_id"] == "test123"

    second = json.loads(lines[1])
    assert second["type"] == "user_message"
    assert second["content"] == "hello"
    assert second["is_final"] is True

    third = json.loads(lines[2])
    assert third["type"] == "tool_start"
    assert third["tool"] == "run_process"

    fourth = json.loads(lines[3])
    assert fourth["type"] == "agent_response"
    assert fourth["content"] == "done"
