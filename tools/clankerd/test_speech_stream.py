import asyncio
import json
import threading

import pytest
from langchain_core.messages import AIMessage
from langgraph.prebuilt import ToolNode
from langgraph.graph import MessagesState, StateGraph, START, END

from tools.clankerd import agent
from tools.clankerd.speech_stream import (
    BoundarySegmenter, CURRENT_SPEECH, SpeechCoordinator, speak_prefix,
)
from tools.voiced.tts import SpeechCancelled


class RecordingClient:
    def __init__(self):
        self.calls = []
        self.first_segment = threading.Event()
        self.release = None

    def speak_segments(self, segments, **kwargs):
        call = {"segments": [], "lang": kwargs["lang"]}
        self.calls.append(call)
        for segment in segments:
            if kwargs["stop_event"].is_set():
                raise SpeechCancelled("cancelled")
            call["segments"].append(segment)
            self.first_segment.set()
            if self.release:
                assert self.release.wait(3)
        return "test.wav"


def delta(coordinator, args, *, call_id="call-a", run="model-a", name="speak", index=0):
    coordinator.feed(run, [{"index": index, "id": call_id, "name": name, "args": args}])


@pytest.mark.parametrize("text", ['Hello. A "quote", a \\slash, and a newline.\nNext sentence.', 'A musical symbol: 𝄞. Smile 😀. Done.', '中文。下一句！'])
def test_json_prefix_never_emits_partial_escape_or_surrogate(text):
    raw = json.dumps({"lang": "en", "background": False, "text": text})
    previous = ""
    for end in range(len(raw) + 1):
        fields, _ = speak_prefix(raw[:end])
        current = fields.get("text", "")
        assert current.startswith(previous)
        assert text.startswith(current)
        assert not any(0xD800 <= ord(c) <= 0xDFFF for c in current)
        previous = current
    assert previous == text


def test_boundaries_abbreviations_decimals_and_final_tail():
    segmenter = BoundarySegmenter()
    assert segmenter.feed("Dr. Smith paid 3.") == []
    assert segmenter.feed('14 dollars. "Really?" Next') == ['Dr. Smith paid 3.14 dollars. ', '"Really?" ']
    assert segmenter.feed(" sentence", final=True) == ["Next sentence"]
    clause = BoundarySegmenter("clause")
    assert clause.feed("One clause, another") == ["One clause, "]


@pytest.mark.asyncio
async def test_first_sentence_starts_before_tool_arguments_finish_and_no_replay():
    client = RecordingClient()
    speech = SpeechCoordinator(client=client)
    try:
        delta(speech, '{"lang":"en","text":"First sentence. Sec')
        assert await asyncio.to_thread(client.first_segment.wait, 2)
        assert client.calls[0]["segments"] == ["First sentence. "]
        delta(speech, 'ond sentence."}', name="", call_id="")
        speech.model_end("model-a")
        await speech.complete("call-a", "First sentence. Second sentence.", "en", False)
        assert len(client.calls) == 1
        assert "".join(client.calls[0]["segments"]) == "First sentence. Second sentence."
        # A delayed event must not re-create completed playback.
        delta(speech, "", name="", call_id="")
        assert not speech.sessions
    finally:
        await speech.shutdown()


@pytest.mark.asyncio
async def test_language_after_text_waits_and_preserves_non_english():
    client = RecordingClient()
    speech = SpeechCoordinator(client=client)
    try:
        delta(speech, '{"text":"Bonjour. Deuxième phrase.')
        await asyncio.sleep(.03)
        assert not client.calls
        delta(speech, '","lang":"fr"}', name="", call_id="")
        await speech.complete("call-a", "Bonjour. Deuxième phrase.", "fr", False)
        assert client.calls == [{"segments": ["Bonjour. ", "Deuxième phrase."], "lang": "fr"}]
    finally:
        await speech.shutdown()


@pytest.mark.asyncio
async def test_toolnode_joins_early_session_using_injected_call_id():
    client = RecordingClient()
    speech = SpeechCoordinator(client=client)
    token = CURRENT_SPEECH.set(speech)
    try:
        delta(speech, '{"lang":"en","text":"Speak once. Still streaming')
        assert await asyncio.to_thread(client.first_segment.wait, 2)
        text = "Speak once. Still streaming."
        node = ToolNode([agent.speak])
        graph = StateGraph(MessagesState)
        graph.add_node("tools", node)
        graph.add_edge(START, "tools")
        graph.add_edge("tools", END)
        result = await graph.compile().ainvoke({"messages": [AIMessage(content="", tool_calls=[{
            "id": "call-a", "name": "speak", "args": {"text": text, "lang": "en", "background": False},
        }])]})
        assert "Spoke:" in result["messages"][-1].content
        assert len(client.calls) == 1
        assert "".join(client.calls[0]["segments"]) == text
    finally:
        CURRENT_SPEECH.reset(token)
        await speech.shutdown()


@pytest.mark.asyncio
async def test_fifo_background_calls_and_scoped_tool_indexes():
    client = RecordingClient()
    client.release = threading.Event()
    speech = SpeechCoordinator(client=client)
    try:
        delta(speech, '{"lang":"en","text":"First."}')
        await speech.complete("call-a", "First.", "en", True)
        delta(speech, '{"lang":"en","text":"Second."}', run="model-b", call_id="call-b")
        await speech.complete("call-b", "Second.", "en", True)
        assert await asyncio.to_thread(client.first_segment.wait, 2)
        assert len(client.calls) == 1
        client.release.set()
        await asyncio.wait_for(speech.queue.join(), 3)
        assert [call["segments"] for call in client.calls] == [["First."], ["Second."]]
    finally:
        client.release.set()
        await speech.shutdown()


@pytest.mark.asyncio
async def test_cancel_incomplete_call_and_malformed_json_do_not_replay():
    client = RecordingClient()
    speech = SpeechCoordinator(client=client)
    try:
        delta(speech, '{"lang":"en","text":"Not yet a sentence')
        speech.end_run({"model-a"}, cancelled=True)
        await asyncio.wait_for(speech.queue.join(), 2)
        assert not client.calls
        delta(speech, '{"lang":"en","text":"bad\\q', run="model-b", call_id="call-b")
        with pytest.raises(ValueError):
            await speech.complete("call-b", "bad", "en", False)
        await asyncio.wait_for(speech.queue.join(), 2)
        assert not client.calls
    finally:
        await speech.shutdown()


@pytest.mark.asyncio
async def test_other_tool_is_not_intercepted_and_missing_language_falls_back():
    client = RecordingClient()
    speech = SpeechCoordinator(client=client)
    try:
        delta(speech, '{"command_line":"echo hello"}', name="run_bash")
        assert not speech.sessions
        delta(speech, '{"text":"Hello. More text."}', run="model-b", call_id="call-b")
        await asyncio.sleep(.02)
        assert not client.calls
        await speech.complete("call-b", "Hello. More text.", "en", False)
        assert "".join(client.calls[0]["segments"]) == "Hello. More text."
    finally:
        await speech.shutdown()


@pytest.mark.asyncio
async def test_model_end_finishes_valid_calls_and_cancels_invalid_fifo_head():
    client = RecordingClient()
    speech = SpeechCoordinator(client=client)
    try:
        delta(speech, '{"lang":"en"}')  # Invalid first call must not block the FIFO.
        delta(speech, '{"lang":"en","text":"Second call."}', call_id="call-b", index=1)
        speech.model_end("model-a")
        await asyncio.wait_for(speech.queue.join(), 2)
        assert client.calls == [{"segments": ["Second call."], "lang": "en"}]
        # Even if playback completes before ToolNode runs, it must join, not replay.
        await speech.complete("call-b", "Second call.", "en", False)
        assert len(client.calls) == 1
    finally:
        await speech.shutdown()


@pytest.mark.asyncio
async def test_pinned_language_can_start_when_text_arrives_first():
    client = RecordingClient()
    speech = SpeechCoordinator(client=client, language="en")
    try:
        delta(speech, '{"text":"English can start now. Still writing')
        assert await asyncio.to_thread(client.first_segment.wait, 2)
        assert client.calls[0]["lang"] == "en"
        await speech.complete("call-a", "English can start now. Still writing.", "en", False)
        assert "".join(client.calls[0]["segments"]) == "English can start now. Still writing."
    finally:
        await speech.shutdown()
