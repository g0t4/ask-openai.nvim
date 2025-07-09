from pydantic import BaseModel
from typing import TypeVar, Callable, Any
import json

def cheap_serialize(obj):
    """ use basic reflection of python's primitive types and pydantic models"""
    if isinstance(obj, BaseModel):
        return obj.model_dump()
    elif isinstance(obj, (str, int, float, bool)) or obj is None:
        return obj
    elif isinstance(obj, list):
        return [cheap_serialize(x) for x in obj]
    elif isinstance(obj, dict):
        return {k: cheap_serialize(v) for k, v in obj.items()}
    else:
        raise TypeError(f"Don't know how to serialize {type(obj)}")

def to_json(obj):
    return json.dumps(cheap_serialize(obj), indent=2)

def from_json(obj):
    return json.loads(obj)

T = TypeVar('T')

def read_dict_str_model(path, ctor: Callable[[Any], T]) -> dict[str, T]:
    with open(path, 'r') as f:
        return {k: ctor(v) for k, v in json.load(f).items()}

def write_json(obj, path):
    with open(path, 'w') as f:
        json.dump(cheap_serialize(obj), f, indent=2)

def read_json(path):
    with open(path, 'r') as f:
        return json.load(f)
