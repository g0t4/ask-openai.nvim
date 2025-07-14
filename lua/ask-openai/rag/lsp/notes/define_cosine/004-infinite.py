# this smells like PI time :)... but, I am going to do this step by step and not jump yet

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

arr = None
for i in np.arange(0, 10, 0.05):

    # a_s = np.arange(1, -1.01, -0.05)
    a = i % 4 - 1
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
