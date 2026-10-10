"""Pytest tests for the macOS fn-key PTT callback logic."""

from __future__ import annotations

from types import SimpleNamespace

import tools.voiced.ptt as ptt_module
from tools.voiced.ptt import PushToTalk, _event_tap_callback


def _fake_quartz(monkeypatch):
    """Install a minimal fake Quartz module and return its namespace."""
    fake = SimpleNamespace(
        kCGEventFlagsChanged=1,
        kCGEventKeyDown=2,
        kCGEventKeyUp=3,
        kCGKeyboardEventKeycode=4,
        kCGEventFlagMaskSecondaryFn=0x800000,
        kCGEventTapOptionDefault=0,
        kCGHeadInsertEventTap=0,
        kCGSessionEventTap=0,
        kCFRunLoopDefaultMode=0,
        CGEventGetIntegerValueField=lambda event, field: event["keycode"],
        CGEventGetFlags=lambda event: event["flags"],
        CGEventMaskBit=lambda bit: 1 << bit,
        CGEventTapCreate=lambda *args, **kw: object(),
        CFMachPortCreateRunLoopSource=lambda *args: object(),
        CFRunLoopAddSource=lambda *args: None,
        CGEventTapEnable=lambda *args: None,
        CFRunLoopRun=lambda: None,
    )
    monkeypatch.setattr(ptt_module, "Quartz", fake)
    return fake


def test_fn_key_press_and_release(monkeypatch):
    _fake_quartz(monkeypatch)

    events = []
    ptt = PushToTalk(
        on_press=lambda: events.append("press"),
        on_release=lambda: events.append("release"),
    )

    fn_pressed = {"keycode": ptt_module.FN_KEYCODE, "flags": 0x800000}
    fn_released = {"keycode": ptt_module.FN_KEYCODE, "flags": 0}

    # fn press -> press, fn release -> release
    _event_tap_callback(None, 1, fn_pressed, ptt)
    _event_tap_callback(None, 1, fn_released, ptt)
    assert events == ["press", "release"]


def test_other_keys_ignored(monkeypatch):
    _fake_quartz(monkeypatch)

    events = []
    ptt = PushToTalk(
        on_press=lambda: events.append("press"),
        on_release=lambda: events.append("release"),
    )

    # A normal key down (non-flagsChanged) must be ignored.
    _event_tap_callback(None, 2, {"keycode": 1, "flags": 0}, ptt)
    # flagsChanged for a non-fn key must be ignored.
    _event_tap_callback(None, 1, {"keycode": 2, "flags": 0x800000}, ptt)
    assert events == []

