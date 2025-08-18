from dataclasses import dataclass
from datetime import datetime

@dataclass
class Customer():
    id: int
    name: str
    email: str
    phone: str
    address: str
    created_at: datetime
    updated_at: datetime
