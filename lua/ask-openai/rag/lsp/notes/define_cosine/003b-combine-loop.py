# this smells like PI time :)... but, I am going to do this step by step and not jump yet

# !!! ok this was a fun exercise to get points evenly spaced and it at least appears close to spaced out! based on initial step size of a then all subsequents steps are set so that a_diff^2 + b_diff^2 == c_diff^2 such that c_diff^2 is constant across all points
# as you take this to zero, you would get a concept of theta then
# c_diff^2 is the lenght of the line between consecutive points, so it IS NOT the arc but it is an approximation
#   and as c_diff => 0 then it becomes the arc  and you can then sum that to get the circumference
#   I think... I am still playing with this new way of thinking about this and need some more tinkering


from matplotlib.axes import Axes
from matplotlib.figure import Figure
from matplotlib.patches import FancyArrow
import numpy as np
import matplotlib.pyplot as plt
# from matplotlib.animation import FuncAnimation
import math

fig: "Figure"
ax1: "Axes"
ax2: "Axes"
fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(10, 5))
fixed_view = 1.5
ax1.set_xlim(-fixed_view, fixed_view)
ax1.set_ylim(-fixed_view, fixed_view)
ax1.set_aspect("equal")  # that way if window aspect ratio isn't 1:1 it won't skew the axes

fixed_view2 = 1.5
ax2.set_xlim(-fixed_view2, fixed_view2)
ax2.set_ylim(-fixed_view2, fixed_view2)
ax2.set_aspect("equal")  # that way if window aspect ratio isn't 1:1 it won't skew the axes

plt.ion()
plt.show()

scatter_x, scatter_y = [], []

first = True
arr: FancyArrow
a = 1
b = 0
a_diff = None
outer_count_limit = 0 # just in case set count max so you can troubleshoot
while a >= -1 and outer_count_limit < 1000:
    outer_count_limit += 1
    if a_diff == None:
        # first step size:
        # !!! as a_diff's initial values => 0 then you get points spaced evenly around the circumference of the circle
        # TRY THESE VALUES:
        # a_diff = 0.05  # !!!! ADJUST THIS to get diff set of similarly spaced points
        a_diff = 0.02
        # a_diff = 0.01
        # a_diff = 0.005
        a_diff = 0.002
    else:
        arr.remove()
        a_proposed_diff = a_diff
        inner_count_limit = 0
        while inner_count_limit < 9000:
            inner_count_limit += 1
            # print(f" loop")
            a_proposed = a - a_proposed_diff
            _a_prop_sq = math.pow(a_proposed, 2)
            if np.round(_a_prop_sq, 6) > 1:
                print(f'  {_a_prop_sq=}')
                # TODO stop outer loop too, do not plot!
                break
            b_proposed = math.sqrt(1 - _a_prop_sq)
            # print(f"  {a_proposed},{b_proposed}")
            a_proposed_diff_sq = math.pow(a_proposed_diff, 2)
            b_proposed_diff_sq = math.pow(b_proposed - b, 2)
            c_proposed_diff_sq = a_proposed_diff_sq + b_proposed_diff_sq
            # SOLVING THIS SUCH THAT
            # c_diff_sq[previous] == c_diff_sq[proposed]
            # ! draw out first unit vector (1,0) then second one (a[1],b[1]) and then look at how you would calculate the length of the line between the two points (tips of unit vector)... that is how you get to c_diff^2 = a_diff^2 + b_diff^2
            if (c_proposed_diff_sq > (c_diff_sq + 0.00001)):
                a_proposed_diff = a_proposed_diff - 0.0001
            elif (c_proposed_diff_sq < (c_diff_sq - 0.00001)):
                # decrease 1_proposed_difff slightly (small enough I can ignore overcorrections mostly)
                a_proposed_diff = a_proposed_diff + 0.0001
            else:
                print("  break")
                break
        print(f"  {a_proposed_diff=}")
        a_diff = a_proposed_diff

        # %%

    a_next = a - a_diff
    _a_next_sq = math.pow(a_next, 2)
    if _a_next_sq > 1:
        print(f"clipped: {_a_next_sq}")
        break
    b_next = math.sqrt(1 - _a_next_sq)
    a_diff_sq = math.pow(a_diff, 2)
    b_diff_sq = math.pow(b_next - b, 2)
    c_diff_sq = a_diff_sq + b_diff_sq

    print(f"  {c_diff_sq=}")
    print(f"{a_next},{b_next}")
    arr = ax1.arrow(0, 0, a_next, b_next, head_width=0.05, head_length=0.1, length_includes_head=True)

    # first up, a vs b over time... draw the circle!
    scatter_x.append(a_next)
    scatter_y.append(b_next)
    ax2.scatter(scatter_x[-1], scatter_y[-1], color='red')

    plt.pause(0.02)
    a = a_next
    b = b_next

print()
# # exit()
#
# a_s = np.arange(-1, 1.01, 0.05)
# for a in a_s:
#     if arr:
#         arr.remove()
#     b = -math.sqrt(
#             1 - \
#             np.clip(math.pow(a, 2), 0, 1) \
#         )
#     print(a, b)
#     arr = ax1.arrow(0, 0, a, b, head_width=0.05, head_length=0.1, length_includes_head=True)
#
#     # first up, a vs b over time... draw the circle!
#     scatter_x.append(a)
#     scatter_y.append(b)
#     ax2.scatter(scatter_x[-1], scatter_y[-1], color='red')
#
#     plt.pause(0.02)
