import time


class Timer:

    def __init__(self, message=""):
        self.message = message

    def __enter__(self):
        self.start_ns = time.time_ns()
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        self.end_ns = time.time_ns()
        elapsed_ns = self.end_ns - self.start_ns
        elapsed_ms = elapsed_ns / 1000000
        print(f"wall time ({self.message}): {elapsed_ms:,.2f} ms")


