from dataclasses import dataclass

def log_calls(func):

    def log_and_call(*args, **kwargs):
        print("before")
        return func(*args, **kwargs)

    return log_and_call

@log_calls
def func1():
    return 1

@dataclass
class MyPoint:
    x: int
    y: int

    @log_calls
    def repr(self):
        return f"({self.x}, {self.y})"
