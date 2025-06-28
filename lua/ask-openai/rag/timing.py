import time

from rich import print

class Timer:

    def __init__(self, finished_message=""):
        self.finished_message = finished_message

    def __enter__(self):
        self.start_ns = time.time_ns()
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        self.end_ns = time.time_ns()
        elapsed_ns = self.end_ns - self.start_ns
        elapsed_ms = elapsed_ns / 1000000
        print(f"wall time ({self.finished_message}): {elapsed_ms:,.2f} ms")
