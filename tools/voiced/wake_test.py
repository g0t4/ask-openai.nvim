"""Tests for the wake-word / stop-word detector."""

from __future__ import annotations

from tools.voiced.wake import detect, is_stop, is_wake


def test_wake_variants():
    assert is_wake("clanker clanker")
    assert is_wake("Clanker, clanker")
    assert is_wake("clanker, clanker, clanker")
    assert is_wake("CLANKER CLANKER")
    assert is_wake("hey clanker clanker")


def test_stop_variants():
    assert is_stop("over")
    assert is_stop("Over.")
    assert is_stop("out")
    assert is_stop("done")
    assert is_stop("that's all")
    assert is_stop("standby")


def test_ambiguous_and_noise():
    assert detect("clanker") is None
    assert detect("clank") is None
    assert detect("hello there") is None
    assert detect("") is None


def test_stop_priority():
    assert is_stop("over and out")
    assert is_stop("done, thanks")
