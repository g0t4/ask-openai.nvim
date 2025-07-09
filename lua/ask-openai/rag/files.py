from pydantic import BaseModel
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
