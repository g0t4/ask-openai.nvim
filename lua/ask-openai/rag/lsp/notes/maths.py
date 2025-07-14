import numpy as np
from rich import print
import math
from assertpy import assert_that

vec = [1, 3, -5]

magnitude = lambda vector: math.sqrt(sum([c * c for c in vector]))

assert_that(magnitude(vec)).is_close_to(5.916, tolerance=0.001)

# %%

vec_np = np.array(vec)
print(vec_np)

# use dot product relationship to magnitude to compute magnitude:
dot_prod = vec_np.dot(vec_np.T)
print(dot_prod)
mag = np.sqrt(dot_prod)
print(mag)

# if does not blow up then its true:
# mag^2 == dot_prod
assert_that(math.pow(mag, 2)).is_equal_to(dot_prod)

# %%

# definitionally:
#   cos(θ) = adjacent/hypotenuse
# and:
#   a^2 + b^2 = c^2
#   ==> c = sqrt(a^2 + b^2)
# then, restate:
#   a == adjacent, c = hypotenuse
#
#   ==> cos(θ) = a / c
# therefore:
#   cos(θ) = a / c  = a/sqrt(a^2+b^2)
#
# take two unit vectors that start out fully overlapping
#   --->
#   start at origin, point right only
#   magnitude 1 for both
#   all in a/x component
#
#   throughout this exercise, they will both remain unit vectors (magnitued = 1)
#   I want to slowly rotate one around origin, until it gets to a right angle where it has no x-axis component, and y=1 for its y component (b/c its always a unit vector)
#   just thinking about this w/o any math yet
#   - when right angle with one unit vector pointing up or down, fully... (all in the y component) then there is NO OVERLAP (0)
#     θ=90 => cos(90°) = 0
#     θ=270 => cos(270°) = 0
#   - when fully overlap => overlap is 1
#     θ=0 => cos(0°) = 1
#   - when one left (fully, no y component) then the overlap == -1
#     θ=180 => cos(180°) = -1
#
# to do this, I will plot it as taking the a (x-axis) component and decreasing it
#   which means its b has to increase as its a decreases, to match a magnitude of 1
#   using this formula:
#     a/sqrt(a^2+b^2)
#     aka:
#     x/sqrt(x^2+y^2)
#
# ok now
#   a^2 + b^2 = c^2 (c is hypotenuse or mag... == 1)
#   a^2 + b^2 = 1
#   b = sqrt(1-a^2)
#   a starts at 1, b = 0
#   eventually a => 0, b => 1
#   then a => -1 while b => 0
#   then a => 0 while b => -1
#   finally a => 1 while b => 0
#
#
# if I plot a vs b => turns into a circle
#
# if I plot cos(θ) => I then need to vary b as a function of a:
#    b = sqrt(1-a^2)
#    and then I plot
#    a/sqrt(a^2+b^2)

# take two unit vectors
# theta (angle between)

# θ = 0° = full overlap
#  => 1

# 45 degrees
# a^2 + b^2 = c^2
# a = b => 2a^2 = c^2 => a^2 = c^2/2 => a = sqrt(c^2/2) => a = c/sqrt(2)
# => a/c = 1/sqrt(2) = cos(theta) => ~0.71

# FYI maybe use
# a^2 + b^2 = c^2
# =>   a = adjacent, b = opposite, c = hypotenuse
# a^2 + o^2 = h^2

# 90 degrees = no overlap
#  => 0

# 180 degrees = inverted overlap (fully)
#  => -1

# 270 degrees = no overlap
#  => 0

# 360 == 0 => full overlap
#  => 1

# %%

import numpy as np
import matplotlib.pyplot as plt
# from matplotlib.animation import FuncAnimation
import math

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

a_s = np.arange(1, -1.01, -0.05)
arr = None
for a in a_s:
    if arr:
        arr.remove()
    b = math.sqrt(
            1 - \
            np.clip(math.pow(a, 2), 0, 1) \
        )
    print(a, b)
    arr = ax1.arrow(0, 0, a, b, head_width=0.05, head_length=0.1, length_includes_head=True)

    # first up, a vs b over time... draw the circle!
    scatter_x.append(a)
    scatter_y.append(b)
    ax2.scatter(scatter_x[-1], scatter_y[-1], color='red')

    plt.pause(0.02)
