import numpy as np
import torch
import os

def env_var_force_cpu() -> str | None:
    # i.e. when my GPU doesn't have room :)
    return os.getenv("ACCELERATE_USE_CPU")

def auto_device():
    force_cpu = env_var_force_cpu()
    if force_cpu:
        return torch.device("cpu")

    return torch.device(
        'cuda' if torch.cuda.is_available() else \
        'mps' if torch.backends.mps.is_available() else \
        'cpu'
    )

def print_type(what):
    if type(what) is np.ndarray:
        print(f'{type(what)} shape: {what.shape} {what.dtype}')
        return

    print(type(what))
