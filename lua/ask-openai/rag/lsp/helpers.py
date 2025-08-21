def auto_device():
    import torch
    device = torch.device(
        'cuda' if torch.cuda.is_available() else \
        'mps' if torch.backends.mps.is_available() else \
        'cpu'
    )
    return device

def print_type(what):
    import numpy as np
    if type(what) is np.ndarray:
        print(f'{type(what)} shape: {what.shape} {what.dtype}')
        return

    print(type(what))

def typeit(x, name="var"):
    cls = type(x)
    mod = cls.__module__
    bits = [f"{name}: {mod}.{cls.__name__}"]
    if hasattr(x, "shape"):
        try:
            bits.append(f"shape={tuple(getattr(x, 'shape'))}")
        except Exception:
            pass
    if hasattr(x, "dtype"):
        try:
            bits.append(f"dtype={str(getattr(x, 'dtype'))}")
        except Exception:
            pass
    if mod.startswith("torch") and hasattr(x, "device"):
        bits.append(f"device={getattr(x, 'device')}")
    if hasattr(x, "__len__") and not isinstance(x, (str, bytes)):
        try:
            bits.append(f"len={len(x)}")
        except Exception:
            pass
    return ", ".join(bits)
