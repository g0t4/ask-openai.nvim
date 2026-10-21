"""Use the real terminal dimensions instead of stale exported COLUMNS/LINES."""
import os
import sys

from textual.app import App


class TerminalSizedApp(App):
    def get_driver_class(self):
        driver = super().get_driver_class()
        if os.name == "nt":
            return driver
        from textual.drivers.linux_driver import LinuxDriver
        if not issubclass(driver, LinuxDriver):
            return driver

        class TerminalSizeDriver(driver):
            def _get_terminal_size(self):
                # Textual uses shutil.get_terminal_size(), which prioritizes
                # inherited environment variables. Query the actual TTY first,
                # on startup and on every SIGWINCH/terminal resize.
                for stream in (sys.__stderr__, sys.__stdout__, sys.__stdin__):
                    try:
                        size = os.get_terminal_size(stream.fileno())
                        if size.columns > 0 and size.lines > 0:
                            return size.columns, size.lines
                    except (AttributeError, OSError, ValueError):
                        continue
                return super()._get_terminal_size()

        return TerminalSizeDriver
