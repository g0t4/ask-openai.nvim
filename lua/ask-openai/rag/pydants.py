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


# ! DO NOT MOVE READ here... it is best left inline... even if seems repetitive... don't much it up here for very little (if any) savings for two uses!
def to_json(obj):
    return json.dumps(cheap_serialize(obj), indent=2)

def write_json(obj, path):
    with open(path, 'w') as f:
        json.dump(cheap_serialize(obj), f, indent=2)
