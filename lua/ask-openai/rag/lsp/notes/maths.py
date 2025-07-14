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

# cos(θ) = adjacent/hypotenuse

# take two unit vectors
# theta (angle between)

# θ = 0 degrees = full overlap
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

import matplotlib.pyplot as plt

plt.quiver(0, 0, 1, 2, angles='xy', scale_units='xy', scale=1)
plt.xlim(-1, 3)
plt.ylim(-1, 3)
plt.grid()
plt.show()
