"""Decode streamed speak arguments, segment text, and own exactly one playback.

Only stable JSON string prefixes are exposed. Language must be known before
segments are released. The completed tool invocation validates and joins the
same session; it never replays its text through a second speak operation.
"""
from __future__ import annotations

import asyncio
from contextvars import ContextVar
from dataclasses import dataclass
import json
import logging
import os
import queue
import re
import threading

from tools.voiced.tts import SERVER_VOICE_REF, SpeechCancelled, TTSClient

LOG = logging.getLogger(__name__)
CURRENT_SPEECH = ContextVar("clankerd_speech", default=None)
MAX_ARGUMENT_CHARS = 65536


def _string_prefix(raw, start):
    """Decode one JSON string, retaining incomplete escapes for the next delta."""
    out = []
    i = start + 1
    while i < len(raw):
        c = raw[i]
        if c == '"':
            return "".join(out), i + 1, True
        if c == "\\":
            if i + 1 >= len(raw):
                break
            size = 6 if raw[i + 1] == "u" else 2
            if i + size > len(raw):
                break
            if size == 6:
                code = int(raw[i + 2:i + 6], 16)
                if 0xD800 <= code <= 0xDBFF:
                    if i + 12 > len(raw):
                        break
                    if raw[i + 6:i + 8] != "\\u" or not 0xDC00 <= int(raw[i + 8:i + 12], 16) <= 0xDFFF:
                        raise ValueError("Invalid JSON surrogate pair")
                    size = 12
                elif 0xDC00 <= code <= 0xDFFF:
                    raise ValueError("Unpaired JSON surrogate")
            out.append(json.loads('"' + raw[i:i + size] + '"'))
            i += size
        else:
            if ord(c) < 32 or 0xD800 <= ord(c) <= 0xDFFF:
                raise ValueError("Invalid character in JSON string")
            out.append(c)
            i += 1
    return "".join(out), i, False


def speak_prefix(raw):
    """Return completed fields plus a stable, possibly unfinished text string."""
    fields = {}
    closed = False
    pos = 0
    decoder = json.JSONDecoder()
    raw = raw.lstrip()
    if not raw:
        return fields, closed
    if raw[0] != "{":
        raise ValueError("speak arguments must be an object")
    pos = 1
    while True:
        while pos < len(raw) and raw[pos].isspace():
            pos += 1
        if pos == len(raw) or raw[pos] == "}":
            return fields, closed
        if raw[pos] != '"':
            raise ValueError("Expected JSON field name")
        key, pos, complete = _string_prefix(raw, pos)
        if not complete:
            return fields, closed
        if key in fields:
            raise ValueError("Duplicate speak field")
        while pos < len(raw) and raw[pos].isspace():
            pos += 1
        if pos == len(raw):
            return fields, closed
        if raw[pos] != ":":
            raise ValueError("Expected JSON colon")
        pos += 1
        while pos < len(raw) and raw[pos].isspace():
            pos += 1
        if pos == len(raw):
            return fields, closed
        if raw[pos] == '"':
            value, pos, complete = _string_prefix(raw, pos)
            if key == "text":
                fields[key] = value
                closed = complete
            elif complete:
                fields[key] = value
            if not complete:
                return fields, closed
        else:
            try:
                value, pos = decoder.raw_decode(raw, pos)
            except json.JSONDecodeError:
                return fields, closed
            if key == "text":
                raise ValueError("speak text must be a string")
            fields[key] = value
        while pos < len(raw) and raw[pos].isspace():
            pos += 1
        if pos == len(raw) or raw[pos] == "}":
            return fields, closed
        if raw[pos] != ",":
            raise ValueError("Expected JSON comma")
        pos += 1


class BoundarySegmenter:
    """Conservative sentence boundaries; clause mode is an explicit experiment."""
    ABBREVIATIONS = {"mr.", "mrs.", "ms.", "dr.", "prof.", "sr.", "jr.", "e.g.", "i.e.", "vs.", "etc."}

    def __init__(self, mode="sentence"):
        if mode not in ("sentence", "clause"):
            raise ValueError("Speech boundary must be sentence or clause")
        self.buffer = ""
        punctuation = r"[.!?。！？]" if mode == "sentence" else r"[.!?。！？,;:，；：]"
        self.pattern = re.compile(punctuation + r'''["'”’\)\]]*(?:\s+|(?=[\u3400-\u9fff]))''')

    def feed(self, delta, final=False):
        self.buffer += delta
        segments = []
        start = 0
        for match in self.pattern.finditer(self.buffer):
            candidate = self.buffer[start:match.end()]
            word = candidate.strip().rstrip('"\'”’)]').split()[-1]
            if word.lower() in self.ABBREVIATIONS or re.fullmatch(r"(?:[A-Za-z]\.)+", word):
                continue
            segments.append(candidate)
            start = match.end()
        self.buffer = self.buffer[start:]
        if final and self.buffer:
            segments.append(self.buffer)
            self.buffer = ""
        return [segment for segment in segments if segment.strip()]


class SpeechSession:
    def __init__(self, owner, call_id, model_run):
        self.owner, self.call_id, self.model_run = owner, call_id, model_run
        self.lang = owner.language
        self.prefix = ""
        self.consumed = 0
        self.claimed = False
        self.finished = False
        self.cancelled = False
        self.error = None
        self.segmenter = BoundarySegmenter(owner.boundary)
        # Total argument size is bounded, so text memory is bounded even if
        # generation runs well ahead of the PCM/player queue.
        self.text = queue.Queue()
        self.stop = threading.Event()
        self.done = asyncio.get_running_loop().create_future()
        self.done.add_done_callback(self._observed)

    def _observed(self, future):
        if not future.cancelled() and future.exception():
            LOG.warning("Speech %s failed: %s", self.call_id, future.exception())
        if self.claimed or self.cancelled:
            self.owner.forget(self)

    def event(self, name, **fields):
        if self.owner.trace:
            self.owner.trace.event("speech_" + name, tool_call_id=self.call_id, **fields)

    def update(self, prefix, lang=None, final=False):
        if self.finished:
            return
        if not isinstance(prefix, str) or not prefix.startswith(self.prefix):
            raise ValueError("Streamed speech text changed after emission")
        if lang is not None:
            if not isinstance(lang, str) or not lang:
                raise ValueError("Invalid speech language")
            if self.lang is not None and self.lang != lang:
                raise ValueError("Speech language changed after emission")
            self.lang = lang
        self.prefix = prefix
        if self.lang is None:
            return
        delta = prefix[self.consumed:]
        self.consumed = len(prefix)
        for segment in self.segmenter.feed(delta, final=final):
            self.event("segment_ready", text=segment, language=self.lang)
            self.text.put(segment)

    def finish(self, text, lang):
        if self.error:
            raise self.error
        if self.finished:
            if self.prefix != text or self.lang != lang:
                raise ValueError("Completed speech arguments differ from streamed arguments")
            return
        self.update(text, lang, final=True)
        self.finished = True
        self.text.put(None)

    def cancel(self, error=None):
        if self.cancelled:
            return
        self.cancelled = True
        self.error = error or SpeechCancelled("Speech cancelled")
        self.stop.set()
        self.text.put(None)
        self.event("cancelled", error=str(self.error))

    def segments(self):
        while not self.stop.is_set():
            try:
                text = self.text.get(timeout=0.05)
            except queue.Empty:
                continue
            if text is None:
                return
            yield text

    def play(self):
        # Wait for a first segment before acquiring the shared playback device.
        segments = self.segments()
        first = next(segments, None)
        if first is None:
            raise self.error or ValueError("No speech text received")
        import itertools
        return self.owner.client.speak_segments(
            itertools.chain([first], segments), lang=self.lang,
            speaker_file=SERVER_VOICE_REF, stop_event=self.stop, on_event=self.event,
        )


@dataclass
class PartialCall:
    name: str = ""
    call_id: str = ""
    raw: str = ""


class SpeechCoordinator:
    """FIFO of speech calls, each containing a stream of sentence segments."""
    def __init__(self, trace=None, client=None, boundary=None, language=None):
        self.trace = trace
        self.client = client or TTSClient()
        self.boundary = boundary or os.environ.get("CLANKERD_SPEECH_BOUNDARY", "sentence")
        self.language = language or os.environ.get("CLANKERD_SPEECH_LANGUAGE") or None
        BoundarySegmenter(self.boundary)
        self.calls = {}
        self.sessions = {}
        self.completed = set()
        self.queue = asyncio.Queue()
        self.worker = None

    def session(self, call_id, model_run=None):
        if call_id not in self.sessions:
            session = SpeechSession(self, call_id, model_run)
            self.sessions[call_id] = session
            session.event("stream_started", boundary=self.boundary)
            self.queue.put_nowait(session)
            if self.worker is None:
                self.worker = asyncio.create_task(self._play_loop())
        return self.sessions[call_id]

    def forget(self, session):
        self.sessions.pop(session.call_id, None)
        self.completed.add(session.call_id)
        if len(self.completed) > 1024:
            self.completed.clear()
            self.completed.add(session.call_id)

    def feed(self, model_run, chunks):
        for chunk in chunks:
            key = (model_run, chunk.get("index", 0))
            call = self.calls.setdefault(key, PartialCall())
            name = chunk.get("name") or ""
            if name and name != call.name:
                call.name += name
            call.call_id = chunk.get("id") or call.call_id
            call.raw += chunk.get("args") or ""
            if call.name != "speak" or not call.call_id or call.call_id in self.completed:
                continue
            session = self.session(call.call_id, model_run)
            try:
                if len(call.raw) > MAX_ARGUMENT_CHARS:
                    raise ValueError("Speech arguments exceed buffering limit")
                fields, text_closed = speak_prefix(call.raw)
                session.update(fields.get("text", ""), fields.get("lang"), final=text_closed)
            except (ValueError, TypeError) as error:
                session.cancel(error)

    def model_end(self, model_run):
        for (run, _), call in list(self.calls.items()):
            if run != model_run:
                continue
            if call.name == "speak" and call.call_id in self.sessions:
                try:
                    # Reject a malformed final JSON object. Audio already heard
                    # cannot be retracted, but no remainder or replay is allowed.
                    arguments = json.loads(call.raw)
                    if not isinstance(arguments.get("text"), str) or not isinstance(arguments.get("background", False), bool):
                        raise ValueError("Invalid completed speak arguments")
                    self.sessions[call.call_id].finish(arguments["text"], arguments.get("lang", "en"))
                except (ValueError, KeyError, TypeError, AttributeError) as error:
                    self.sessions[call.call_id].cancel(error)

    async def complete(self, call_id, text, lang, background):
        if call_id in self.completed:
            raise ValueError("Speech tool call already completed")
        session = self.session(call_id)
        session.claimed = True
        try:
            session.finish(text, lang)
        except Exception as error:
            session.cancel(error)
            raise
        if background:
            if session.done.done():
                self.forget(session)
                if session.done.exception():
                    raise session.done.exception()
            return
        try:
            await asyncio.shield(session.done)
        except asyncio.CancelledError:
            session.cancel()
            raise
        finally:
            if session.done.done():
                self.forget(session)

    async def _play_loop(self):
        while True:
            session = await self.queue.get()
            try:
                result = await asyncio.to_thread(session.play)
                if session.error:
                    raise session.error
                session.done.set_result(result)
            except Exception as error:
                session.done.set_exception(error)
            finally:
                self.queue.task_done()

    def end_run(self, model_runs, cancelled=False):
        for session in list(self.sessions.values()):
            if session.model_run in model_runs and (cancelled or not session.claimed):
                session.cancel()
        self.calls = {key: call for key, call in self.calls.items() if key[0] not in model_runs}

    async def shutdown(self):
        for session in list(self.sessions.values()):
            session.cancel()
        if self.worker:
            await self.queue.join()
            self.worker.cancel()
            try:
                await self.worker
            except asyncio.CancelledError:
                pass
