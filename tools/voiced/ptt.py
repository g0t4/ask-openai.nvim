"""Push-to-talk detection for macOS.

Primary trigger: holding down the fn key (kVK_Function = 63) is detected via
a Quartz CGEventTap. Because an event tap requires Accessibility permission,
we also expose ``press`` / ``release`` (driven by socket commands) so PTT works
even before/without that permission.
"""

from __future__ import annotations

import threading
from typing import Callable, Optional

from tools.voiced.voiced_logger import get_logger

logger = get_logger(__name__)

# kVK_Function: the fn (globe) key on Apple keyboards
FN_KEYCODE = 63

try:  # only available on macOS
    import Quartz
except ImportError:  # pragma: no cover - macOS only
    Quartz = None  # type: ignore[assignment]


def _event_tap_callback(proxy, event_type, event, refcon):
    """Quartz CGEventTap callback; ``refcon`` is the owning PushToTalk."""
    ptt = refcon
    # The fn key does not produce ordinary keyDown/keyUp events; it fires a
    # flagsChanged event whose SecondaryFn flag reflects press/release.
    if event_type != Quartz.kCGEventFlagsChanged:
        return event

    keycode = Quartz.CGEventGetIntegerValueField(
        event, Quartz.kCGKeyboardEventKeycode
    )
    if keycode != FN_KEYCODE:
        return event

    flags = Quartz.CGEventGetFlags(event)
    if flags & Quartz.kCGEventFlagMaskSecondaryFn:
        ptt.press()
    else:
        ptt.release()
    return event


class PushToTalk:
    """Tracks a single PTT press/release, debounced via hardware and socket."""

    def __init__(
        self,
        on_press: Callable[[], None],
        on_release: Callable[[], None],
    ) -> None:
        self._on_press = on_press
        self._on_release = on_release
        self._pressed = False
        self._thread: Optional[threading.Thread] = None

    def press(self) -> None:
        """Begin listening (idempotent)."""
        if self._pressed:
            return
        self._pressed = True
        logger.info("PTT pressed -> start listening")
        self._on_press()

    def release(self) -> None:
        """Stop listening (idempotent)."""
        if not self._pressed:
            return
        self._pressed = False
        logger.info("PTT released -> stop listening")
        self._on_release()

    def is_pressed(self) -> bool:
        return self._pressed

    def start_hardware_listener(self) -> None:
        """Start the macOS fn key listener on a background thread."""
        self._thread = threading.Thread(
            target=self._run_event_tap,
            name="ptt-event-tap",
            daemon=True,
        )
        self._thread.start()

    def _run_event_tap(self) -> None:
        if Quartz is None:
            logger.warning("pyobjc Quartz not available; fn key PTT disabled")
            return

        tap = Quartz.CGEventTapCreate(
            Quartz.kCGSessionEventTap,
            Quartz.kCGHeadInsertEventTap,
            Quartz.kCGEventTapOptionDefault,
            Quartz.CGEventMaskBit(Quartz.kCGEventFlagsChanged),
            _event_tap_callback,
            self,
        )
        if tap is None:
            logger.warning(
                "CGEventTapCreate failed - grant Accessibility permission to "
                "the process running `voiced` for fn key PTT."
            )
            return

        run_loop_source = Quartz.CFMachPortCreateRunLoopSource(None, tap, 0)
        Quartz.CFRunLoopAddSource(
            Quartz.CFRunLoopGetCurrent(),
            run_loop_source,
            Quartz.kCFRunLoopDefaultMode,
        )
        Quartz.CGEventTapEnable(tap, True)
        logger.info("fn key PTT listener active (keycode %d)", FN_KEYCODE)
        Quartz.CFRunLoopRun()
