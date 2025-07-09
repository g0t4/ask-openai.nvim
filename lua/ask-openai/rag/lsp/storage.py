from pydantic import BaseModel

class FileStat(BaseModel):
    mtime: float
    size: int
    hash: str
    path: str

class Chunk(BaseModel):
    id: str
    id_int: str
    text: str
    file: str
    start_line: int
    end_line: int
    type: str
    file_hash: str
