"""Hands-free wake-word activation for the voiced daemon.

While idle, the daemon runs a lightweight continuous listener that watches
for a wake phrase ("clanker, clanker") to begin listening, and a stop phrase
("over" / "out" / "done") to end it. This lets the user talk hands-free
without touching the push-to-talk key.
"""

from __future__ import annotations

import re

from tools.voiced.voiced_logger import get_logger

logger = get_logger(__name__)


def normalise(text: str) -> str:
    """Lowercase, strip punctuation, and collapse whitespace."""
    text = text.lower()
    text = re.sub(r"[^a-z0-9\s]", " ", text)
    return re.sub(r"\s+", " ", text).strip()


WAKE_PHRASES = ("clanker clanker", "clanker clank", "clank clank")
STOP_WORDS = ("over", "out", "done", "standby", "all")
IGNORE_PHRASES = ("clanker", "clank")


def detect(text: str) -> str | None:
    """Return ``"wake"``, ``"stop"``, or ``None`` for a given transcript."""
    n = normalise(text)
    if not n:
        return None

    words = n.split()

    # Wake: the doubled phrase.
    if n in WAKE_PHRASES or n.endswith(WAKE_PHRASES):
        return "wake"

    # Stop: a standalone stop word, or one leading/trailing the utterance.
    if any(w in STOP_WORDS for w in words):
        return "stop"

    # Bare wake word (without the repeat) is ambiguous -> ignore.
    if n in IGNORE_PHRASES:
        return None

    return None


def is_wake(text: str) -> bool:
    return detect(text) == "wake"


def is_stop(text: str) -> bool:
    return detect(text) == "stop"
