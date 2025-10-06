class IndentPrinter:

    def __init__(self, indent_size: int = 2, _print=None):
        self.indent_size = indent_size
        self.current_indent = 0
        if _print is None:
            import rich
            _print = rich.print
        self._print = _print

    def print(self, *args, **kwargs):
        indent_str = " " * (self.current_indent * self.indent_size)
        self._print(indent_str, *args, **kwargs)

    def increment(self):
        self.current_indent += 1

    def decrement(self):
        self.current_indent = max(0, self.current_indent - 1)
