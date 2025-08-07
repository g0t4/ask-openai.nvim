import numpy as np
import torch

def auto_device():
    device = torch.device(
        'cuda' if torch.cuda.is_available() else \
        'mps' if torch.backends.mps.is_available() else \
        'cpu'
    )
    return device

def print_type(what):
    if type(what) is np.ndarray:
        print(f'{type(what)} shape: {what.shape} {what.dtype}')
        return

    print(type(what))
