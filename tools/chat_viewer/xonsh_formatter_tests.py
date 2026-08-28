import json

import pytest

from tools.chat_viewer.xonsh_formatter import parse_run_xonsh_arguments


def test_extracts_code_and_preserves_remaining_arguments():
    arguments = json.dumps({
        "code": "import os\nls -la",
        "cwd": "/tmp",
        "timeout_seconds": 10,
    })

    code, remaining = parse_run_xonsh_arguments(arguments)

    assert code == "import os\nls -la"
    assert remaining == {"cwd": "/tmp", "timeout_seconds": 10}


@pytest.mark.parametrize("arguments", [
    json.dumps({"cwd": "/tmp"}),
    json.dumps({"code": None}),
    json.dumps({"code": ["ls"]}),
])
def test_rejects_missing_or_invalid_code(arguments: str):
    with pytest.raises(ValueError, match="Missing or invalid code argument"):
        parse_run_xonsh_arguments(arguments)


def test_rejects_non_object_arguments():
    with pytest.raises(ValueError, match="arguments must be an object"):
        parse_run_xonsh_arguments("[]")
