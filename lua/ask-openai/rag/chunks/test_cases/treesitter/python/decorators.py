import functools
from dataclasses import dataclass

def log_calls(func):

    @functools.lru_cache()
    def log_and_call_nested(*args, **kwargs):
        print("before")
        return func(*args, **kwargs)

    return log_and_call_nested

@log_calls
@log_calls
def func1():
    return 1

@dataclass
@dataclass
class MyPoint:
    x: int
    y: int

    @log_calls
    def repr(self):
        return f"({self.x}, {self.y})"
