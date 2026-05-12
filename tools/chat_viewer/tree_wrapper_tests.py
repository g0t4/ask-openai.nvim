# test case for TreeWrapper.add

import pytest
from tools.chat_viewer.tree_wrapper import TreeWrapper

def test_create_tree_without_label_nor_parent():
    wrapper = TreeWrapper()
    assert wrapper.label == ""
    assert wrapper.parent == None
