# this smells like PI time :)... but, I am going to do this step by step and not jump yet

# !!! tried to get speed constant but I can't quite tell the difference, esp b/c it only goes half way around before then I switch to loop below and that janks it up and yeah so I need to merge the loops into one and hav smooth transition before I can play with timing and notice smooth vs not smooth movement

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

a_step = 0.05
a_s = np.arange(1, -1.01, -a_step)
arr = None
b_prior = 0
a_prior = 1
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

    b_step = b - b_prior
    # speed_ratio = 1
    speed_ratio = np.abs(b_step) / a_step
    print(f"{a},{b}: {speed_ratio=}")
    if speed_ratio > 0:
        plt.pause(0.02 * speed_ratio)
    b_prior = b
    a_prior = a

# * ok unique observation here is that by varying a linearly  (1 => 0 => -1)
#   by fixed step 0.01
#   the tip of the unit vector drawn are unevenly distributed
#   right away there's a big jump up and then the spacing of points falls off from there
#   as a gets to 0 the points become densly clustered!
#   this means something
# * THEN, I also notice that I need to define b different to capture the bottom half of the circle if you will
#   as -1 => a => 1 ... then I need b inverted
#   this is nothing special, just the convention of expressing the unit vector
#   BUT, I am having trouble then defining an infinite sequence that would allow me to
#      let the animation run in perpituity
#      I could solve this with a loop over two loops.. I will add that change next

a_s = np.arange(-1, 1.01, a_step)
b_prior = 0
a_prior = -1
for a in a_s:
    if arr:
        arr.remove()
    b = -math.sqrt(
            1 - \
            np.clip(math.pow(a, 2), 0, 1) \
        )
    arr = ax1.arrow(0, 0, a, b, head_width=0.05, head_length=0.1, length_includes_head=True)

    # first up, a vs b over time... draw the circle!
    scatter_x.append(a)
    scatter_y.append(b)
    ax2.scatter(scatter_x[-1], scatter_y[-1], color='red')

    b_step = b - b_prior
    # speed_ratio = 1
    speed_ratio = np.abs(b_step) / a_step
    print(f"{a},{b}: {speed_ratio=}")
    if speed_ratio > 0:
        plt.pause(0.02 * speed_ratio)
    b_prior = b
    a_prior = a
