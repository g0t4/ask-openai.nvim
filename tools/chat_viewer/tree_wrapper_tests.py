# test case for TreeWrapper.add

import pytest
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
        # TODO do something better than json for complex values... later
        wrapper.add_sections_from_json_keys('{"key": {"inner": "value"}}')
        assert len(wrapper.children) == 1
        child = wrapper.children[0]
        assert "key" in child.label
        # right now dict is serialized to JSON...
        assert '{"inner": "value"}' in child.label

    def test_primitive_values(self):
        wrapper = TreeWrapper()
        wrapper = TreeWrapper()
        wrapper.add_sections_from_json_keys('{"a": 1, "b": "text", "c": true}')
        assert len(wrapper.children) == 3
        labels = [child.label for child in wrapper.children]
        assert any("a: " in lbl and " 1" in lbl for lbl in labels)
        assert any("b: " in lbl and " text" in lbl for lbl in labels)
        assert any("c: " in lbl and " True" in lbl for lbl in labels)

def test_add_without_label_should_use_empty_string():
    wrapper = TreeWrapper()
    node = wrapper.add()
    assert node.label == ""
