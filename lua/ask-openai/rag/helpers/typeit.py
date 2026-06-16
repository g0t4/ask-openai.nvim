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
