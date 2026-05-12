# test case for TreeWrapper.add

import pytest
from tools.chat_viewer.tree_wrapper import TreeWrapper

def test_create_tree_without_label_nor_parent():
    wrapper = TreeWrapper()
    assert wrapper.label == ""
    assert wrapper.parent == None

def test_sections_from_json_keys():
    wrapper = TreeWrapper()
    wrapper.add_sections_from_json_keys('{"section1": {}, "section2": {}}')
    assert "section1" in wrapper.children[0].label
    assert "section2" in wrapper.children[1].label

def test_add_without_label_should_use_empty_string():
    wrapper = TreeWrapper()
    node = wrapper.add()
    assert node.label == ""
