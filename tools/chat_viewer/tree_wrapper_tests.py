# test case for TreeWrapper.add
import json
import pytest
from io import StringIO
from rich.console import Console

from tools.chat_viewer.tree_wrapper import TreeWrapper

def test_create_tree_without_label_nor_parent():
    wrapper = TreeWrapper()
    assert wrapper.label == ""
    assert wrapper.parent == None

def test_sections_from_json_keys():
    wrapper = TreeWrapper()
    wrapper.add_sections_from_json_keys('{"section1": 1, "section2": 2}')
    assert len(wrapper.children) == 2
    child1 = wrapper.children[0]
    assert child1
    assert "section1" in child1.label
    child2 = wrapper.children[1]
    assert child2
    assert "section2" in child2.label

class TestTreeWrapper_SectionsFromJsonKeys:

    def test_dict_value(self):
        wrapper = TreeWrapper()
        wrapper.add_sections_from_json_keys('{"key": {"inner": "value"}}')

        recorded = self.record_plaintext(wrapper)

        assert """key:
        inner: value""" in recorded

    def record_plaintext(self, tree: TreeWrapper) -> str:
        console = Console(record=True, width=120, force_terminal=False)
        console.print(tree)
        # `export_text` returns a `str` with markup stripped.
        return console.export_text()

    def test_primitive_values_do_not_fail(self) -> None:
        wrapper = TreeWrapper()
        wrapper.add_sections_from_json_keys('{"a": 1, "b": "text", "c": true}')

        recorded = self.record_plaintext(wrapper)

        expected_fragments = [
            # at least make sure no errors writing the values
            "a: 1",
            "b: text",
            "c: True",
        ]

        for fragment in expected_fragments:
            assert fragment in recorded, f"Missing fragment in recorded output: {fragment}"

def test_add_without_label_should_use_empty_string():
    wrapper = TreeWrapper()
    node = wrapper.add()
    assert node.label == ""
