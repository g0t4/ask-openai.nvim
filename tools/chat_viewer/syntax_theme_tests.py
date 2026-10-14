import io
import json
import re

from rich.console import Console

from rich.syntax import Syntax
from xonsh.pyghooks import XonshLexer

from tools.chat_viewer.__main__ import _markdown, add_tool_call_request
from tools.chat_viewer.tree_wrapper import TreeWrapper


def test_markdown_uses_shared_palette_with_wrapping_and_no_background():
    source = '# Project\n\n**Important** `inline`\n\n```python\ndef greet():\n    return "hi\\n"\n```\n'
    rendered = _markdown(source)
    assert rendered.word_wrap is True
    output = io.StringIO()
    Console(file=output, width=100, force_terminal=True, no_color=False, color_system='truecolor').print(rendered)
    ansi = output.getvalue()
    assert '38;2;179;148;227' in ansi  # purple headings and keywords
    assert '38;2;217;189;131' in ansi  # amber emphasis and escapes
    assert '38;2;172;208;149' in ansi  # fenced Python strings
    assert not re.search(r'\x1b\[(?:1m|1;|3m|3;|48;)', ansi)
    assert '# Project' in re.sub(r'\x1b\[[0-9;]*m', '', ansi)


def test_process_and_xonsh_arguments_use_shared_rendering_without_bat(monkeypatch):
    def reject_subprocess(*args, **kwargs):
        raise AssertionError('Tool input rendering must not launch bat')

    monkeypatch.setattr('tools.chat_viewer.__main__.subprocess.run', reject_subprocess)
    cases = [
        ('run_process', {'command_line': 'echo "hello" | cat', 'cwd': '/tmp', 'stdin_text': 'input'}, 'bash'),
        ('run_process', {'argv': ['echo', 'hello world'], 'cwd': '/tmp'}, 'bash'),
        ('run_xonsh', {'code': 'import os\nvalue = $(echo "hello")', 'cwd': '/tmp'}, 'xonsh'),
    ]
    for tool, arguments, language in cases:
        tree = TreeWrapper.hidden_root()
        add_tool_call_request(tool, json.dumps(arguments), tree)
        def walk(node):
            yield node.label
            for child in node.children:
                yield from walk(child)
        renderables = list(walk(tree))
        snippets = [item for item in renderables if isinstance(item, Syntax)]
        assert snippets, (tool, renderables)
        assert language in snippets[0].lexer.aliases
        assert snippets[0].word_wrap is True
        if language == 'xonsh':
            assert isinstance(snippets[0].lexer, XonshLexer)
            assert snippets[0].code == arguments['code']
        elif 'command_line' in arguments:
            assert snippets[0].code == arguments['command_line']
            assert len(snippets) == 2  # stdin retains its separate heredoc block
        else:
            assert snippets[0].code == 'echo "hello world"'
        output = io.StringIO()
        Console(file=output, width=100, force_terminal=True, no_color=False, color_system='truecolor').print(tree)
        assert '/tmp' in output.getvalue()  # remaining metadata still displayed
        assert '38;2;172;208;149' in output.getvalue()  # our string color
