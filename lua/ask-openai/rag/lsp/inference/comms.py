from dataclasses import asdict, dataclass
import socket
from typing import Any
import msgpack
import struct

from ..logs import get_logger

logger = get_logger(__name__)

def recv_exact(sock, content_size):
    buf = b''
    while len(buf) < content_size:
        chunk = sock.recv(content_size - len(buf))
        if not chunk:
            raise ConnectionError("Socket connection closed")
        buf += chunk
    return buf

# https://docs.python.org/3/library/struct.html#format-characters
#   I = unsigned int (4 bytes)
#   c = char (1 byte)
# https://docs.python.org/3/library/struct.html#struct-alignment
#   ! = network order

def recv_len_then_msg(conn: socket.socket) -> dict[str, Any] | None:
    msg_len_packed = recv_exact(conn, 4)
    msg_len = struct.unpack('!I', msg_len_packed)[0]
    if not msg_len:
        return None

    msg_packed = recv_exact(conn, msg_len)
    return msgpack.unpackb(msg_packed, raw=False)

def send_len_then_msg(conn: socket.socket, msg: dict[str, Any]):
    msg_packed = msgpack.packb(msg, use_bin_type=True)
    msg_len = len(msg_packed)
    msg_len_packed = struct.pack('!I', msg_len)  # 4-byte network byte order
    conn.sendall(msg_len_packed + msg_packed)
