import os
import pty
import sys
import termios
import tty
from unittest.mock import Mock

import pytest

from tools.chat_viewer.browser.__main__ import input_loop


def test_browser_keys_preserve_shared_terminal(monkeypatch):
    master, slave = pty.openpty()
    with os.fdopen(master, "wb", buffering=0) as keyboard, os.fdopen(slave, "rb") as terminal:
        monkeypatch.setattr(sys, "stdin", terminal)
        cbreak_flags = termios.ICANON | termios.ECHO
        original_flags = termios.tcgetattr(slave)[3] & cbreak_flags
        browser = Mock()

        def on_char(key):
            assert os.get_blocking(slave)
            if key == b"q":
                raise SystemExit

        browser.on_char.side_effect = on_char
        setcbreak = tty.setcbreak

        def enter_cbreak(fd):
            setcbreak(fd)
            keyboard.write(b"j\x1b[Cq")

        monkeypatch.setattr(tty, "setcbreak", enter_cbreak)
        with pytest.raises(SystemExit):
            input_loop(browser)

        browser.on_csi.assert_called_once_with(b"\x1b[C")
        assert [call.args[0] for call in browser.on_char.call_args_list] == [b"j", b"q"]
        assert os.get_blocking(slave)
        assert termios.tcgetattr(slave)[3] & cbreak_flags == original_flags
