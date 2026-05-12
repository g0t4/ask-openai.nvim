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

class Test_TreeWrapper_add_list_of_key_value_pairs:

    def get_recorded(self, what):
        tree = TreeWrapper()
        tree.add_list_of_key_value_pairs(what)
        return self.record_plaintext(tree)

    def test_value_is_python_dict(self):
        assert "key: string_value" in self.get_recorded({"key": "string_value"})

    def test_value_is_python_list(self):
        recorded = self.get_recorded({"key": ["item1", "item2"]})
        # TODO is this really how I want this to look? each item on its own line if primitive?
        assert """key:
        item1
        item2""" in recorded

    def test_json_dict_value(self):
        tree = TreeWrapper()
        tree.add_sections_from_json_keys('{"key": {"inner": "value"}}')

        recorded = self.record_plaintext(tree)

        assert """key:
        inner: value""" in recorded

    def record_plaintext(self, tree: TreeWrapper) -> str:
        console = Console(record=True, width=120, force_terminal=False)
        console.print(tree)
        # `export_text` returns a `str` with markup stripped.
        return console.export_text()

    def test_primitive_values_do_not_fail(self) -> None:
        tree = TreeWrapper()
        tree.add_sections_from_json_keys('{"a": 1, "b": "text", "c": true}')

        recorded = self.record_plaintext(tree)

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
