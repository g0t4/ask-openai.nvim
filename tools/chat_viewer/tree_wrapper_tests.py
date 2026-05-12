# test case for TreeWrapper.add
import json
import pytest
from io import StringIO
from rich.console import Console

from tools.chat_viewer.tree_wrapper import TreeWrapper

def test_create_tree_without_label_nor_parent():
    tree = TreeWrapper()
    assert tree.label == ""
    assert tree.parent == None

def test_sections_from_json_keys():
    tree = TreeWrapper()
    tree.add_sections_from_json_keys('{"section1": 1, "section2": 2}')
    assert len(tree.children) == 2
    child1 = tree.children[0]
    assert child1
    assert "section1" in child1.label
    child2 = tree.children[1]
    assert child2
    assert "section2" in child2.label

def get_recorded_from_json(json_str):
    tree = TreeWrapper()
    tree.add_sections_from_json_keys(json_str)
    return record_plaintext(tree)

def record_plaintext(tree: TreeWrapper) -> str:
    console = Console(record=True, width=120, force_terminal=False)
    console.print(tree)
    # `export_text` returns a `str` with markup stripped.
    return console.export_text()

class Test_TreeWrapper_add_list_of_key_value_pairs:

    def get_recorded(self, what):
        tree = TreeWrapper()
        tree.add_list_of_key_value_pairs(what)
        return record_plaintext(tree)

    def test_python_dict(self):
        # * scalar types for values in items (key/value pairs)
        assert "key: string_value" in self.get_recorded({"key": "string_value"})
        assert "key: 1" in self.get_recorded({"key": 1})
        assert "key: True" in self.get_recorded({"key": True})
        assert "key: 1.1" in self.get_recorded({"key": 1.1})
        assert "key: None" in self.get_recorded({"key": None})

    def test_python_list(self):
        # TODO is this really how I want this to look? each item on its own line if primitive?
        assert """key:\n        ['item1', 'item2']""" in self.get_recorded({"key": ["item1", "item2"]})
        assert """key:\n        [1, 1.1]""" in self.get_recorded({"key": [1, 1.1]})
        assert """key:\n        [None]""" in self.get_recorded({"key": [None]})
        assert """key:\n        [{'foo': 'bar'}]""" in self.get_recorded({"key": [{"foo": "bar"}]})

    def test_json_dict_value(self):
        json_str = '{"key": {"inner": "value"}}'

        recorded = get_recorded_from_json(json_str)

        assert """key:\n        {'inner': 'value'}""" in recorded

    def test_primitive_values_do_not_fail(self) -> None:
        tree = TreeWrapper()
        tree.add_sections_from_json_keys('{"a": 1, "b": "text", "c": true}')

        recorded = record_plaintext(tree)

        expected_fragments = [
            # at least make sure no errors writing the values
            "a: 1",
            "b: text",
            "c: True",
        ]

        for fragment in expected_fragments:
            assert fragment in recorded, f"Missing fragment in recorded output: {fragment}"

def test_add_without_label_should_use_empty_string():
    tree = TreeWrapper()
    node = tree.add()
    assert node.label == ""
