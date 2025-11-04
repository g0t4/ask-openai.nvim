from tree_sitter import Parser
from lsp.chunks.parsers import get_parser
from rich import print

# %%

lua = get_parser("lua")
for name in dir(lua):
    print(name + ": " + str(getattr(lua, name)))
print(globals().keys())

# %%
# * image with dot graph
tree = lua.parse(b"local a = 1")
with open("lua.graph", "wb") as f:
    tree.print_dot_graph(f)
import subprocess as sp

sp.call("cat lua.graph | dot -Tpng -o lua.png", shell=True)
# lua.reset()

# %%

import rich

dir(rich)

dir(getattr(rich, '__builtins__'))

# %%

def _inspect(parser: Parser, code: bytes):
    tree = parser.parse(code)
    root = tree.root_node
    num_bytes = len(code)
    print(f'{num_bytes=}, last actual byte num: {num_bytes-1}')
    print(f'{root.range}')
    print(f'{root}')
    for c in root.children:
        print(f"  {c.range}")
        print(f"  {c}")

def inspect_lua(code: bytes):
    parser = get_parser("lua")
    _inspect(parser, code)

def inspect_python(code: bytes):
    parser = get_parser("python")
    _inspect(parser, code)

# %%

inspect_lua(b"""
a = 1
b = 2""")

# NOTE: same end_byte=12 as above and there is no byte at position 12 (base0 -> would be 13 total)
#
# num_bytes=12, last actual byte num: 11
# <Range start_point=(1, 0), end_point=(2, 5), start_byte=1, end_byte=12>
#   <Range start_point=(1, 0), end_point=(1, 5), start_byte=1, end_byte=6>
#   (assignment_statement (variable_list name: (identifier)) (expression_list value: (number)))
#   <Range start_point=(2, 0), end_point=(2, 5), start_byte=7, end_byte=12>
#   (assignment_statement (variable_list name: (identifier)) (expression_list value: (number)))
#
# * CONCLUSIONS:
# * - start_point/start_byte are OPEN (inclusive)
# * - end_point and end_byte are CLOSED (not inclusive)

inspect_lua(b"""
a = 1
b = 2
""")

# num_bytes=13, last actual byte num: 12
# <Range start_point=(1, 0), end_point=(3, 0), start_byte=1, end_byte=13>
#   <Range start_point=(1, 0), end_point=(1, 5), start_byte=1, end_byte=6>
#   (assignment_statement (variable_list name: (identifier)) (expression_list value: (number)))
#   <Range start_point=(2, 0), end_point=(2, 5), start_byte=7, end_byte=12>
#   (assignment_statement (variable_list name: (identifier)) (expression_list value: (number)))
# * second node has same end_byte=12 as above even though there is a \n after it
# * NOTE end_byte of root_node differs (it contains the final \n)

# %%

inspect_lua(b"""
    a = 1
    b = 2""")
# * my maths:
# 20 bytes total
# start_point=(1,4) end_point=(1,9)
#     start_byte=5 (base0, 5 bytes before: \n + 4 spaces, so this one starts at 6th byte)
#     end_byte=10 (not inclusive, \n + 9 bytes on this line)
# end_point=(2,4) end_point=(2,9)
#     start_byte=15 (line0: 1 byte, line1: 10 bytes w/ newlin, line2: b is 5th byte => start_byte_base1=16, base0=15)
#     end_byte=20 (not inclusive)
#
# * ACTUAL:
# num_bytes=20, last actual byte num: 19
# <Range start_point=(1, 4), end_point=(2, 9), start_byte=5, end_byte=20>
#   <Range start_point=(1, 4), end_point=(1, 9), start_byte=5, end_byte=10>
#   (assignment_statement (variable_list name: (identifier)) (expression_list value: (number)))
#   <Range start_point=(2, 4), end_point=(2, 9), start_byte=15, end_byte=20>
#   (assignment_statement (variable_list name: (identifier)) (expression_list value: (number)))

#
# * whitespace exists between nodes (intra node is included in Ranges)
# - at node boundaries the whitespace between is not within any node range (especially \n and indentation spaces)
# - THUS, with consecutive nodes, it's important to use start_byte of first, end_byte of last to get all relevant bytes
#   PLUS, indentation before first node on first line
#   - 1. if first node only has whitespace before it on its first line
#        - then, use start_byte -= start_point[1] (columns)
#   - 2. if first node has another full node before it (on first line only)
#        - use prior full node's indentation on the first line as the indent for first node
#        - if multiple full nodes before on first line, use indent of first one on that line
#           - think semicolon delimited statements on one line
#   - 3. if first node has another node before it (partial, IOTW that prior node starts on line above first line)
#        - I am having hard time thinking of cases of this but it's possible
#   - OR
#        - 4. just make a practice of grabbing entire line if any part is uncovered and not fret about what to exclude
#   - PROBABLY CARRY RANGE INFO to consumers so they can decide based on use case, just have uncovered detector return info needed for consumer?
#     OR should it do it all?
#     hard to say, wait for implementation
#

# %%

inspect_python(b"""
a=1
b=2
""")
# num_bytes=9, last actual byte num: 8
# <Range start_point=(1, 0), end_point=(3, 0), start_byte=1, end_byte=9>
#   <Range start_point=(1, 0), end_point=(1, 3), start_byte=1, end_byte=4>
#   (expression_statement (assignment left: (identifier) right: (integer)))
#   <Range start_point=(2, 0), end_point=(2, 3), start_byte=5, end_byte=8>
#   (expression_statement (assignment left: (identifier) right: (integer)))
#

# %%

# ***! careful with multi line strings, IRON.NVIM is FUUUU'ing them up
#   use \n in single line string instead of multiline (or just verify what it actually runs over on the right)
# # for example, the following has 6 lines total w/ 3 trailing newlines!!!?!
# inspect_python(b"""
#     a=1
#     b=2
# """)  # INCORRECT, has 2 extra blank lines at end of doc!
# # something to do with the indentation of a/b b/c if I unindent them then it doesn't happen!
inspect_python(b"""\n    a=1\n    b=2\n""")  # CORRECT
# num_bytes=17, last actual byte num: 16
# <Range start_point=(1, 4), end_point=(3, 0), start_byte=5, end_byte=17>
#   <Range start_point=(1, 4), end_point=(1, 7), start_byte=5, end_byte=8>
#   (expression_statement (assignment left: (identifier) right: (integer)))
#   <Range start_point=(2, 4), end_point=(2, 7), start_byte=13, end_byte=16>
#   (expression_statement (assignment left: (identifier) right: (integer)))

# %%

# FYI cannot have more than two blank lines (nor less) at end of multiline string """
inspect_python(b"""
def adder(a,b):
    return a + b


""")

# practice:
#   root_node (module):
#   - line0: 16 chars w/ \n on end
#      start_point=(0,0)
#      start_byte=0
#   - line1: 16 chars (no \n btw)
#      end_point=(1,15)
#      end_byte=32 (CLOSED_BASE0 => doc has 32 chars and nothing is before first node so it is all in the root node)
#   - only one child node with function_definition
#      same start/end as module (root_node)
#      if add whitespace before def... => neither module(root_node) nor function_definition contain it
#        their offsets simply shift to account for it
#          start_byte += len(added_whitespace_before)
#          start_point[0] += count(added_newlines_before)
#          start_point[1] += count(added_spaces_before_def_on_same_line)
#      if add whitespace after `a + b`... even if just an extra space after `b` ...
#        not added to function_definition node (its end_byte remains unchanged)
#        IS added to root_node (all of it through end of file appears added)
# FYI do not forget, all nodes are tied to root most context, top level (root_node)
# - all whitespace falls into the domain of the root most node!
#    SO technically it's not outside of a node!
#    WAIT... whitespace on line(s) before first node are not part of the root_node!
#     but that is about all I can see at this point
