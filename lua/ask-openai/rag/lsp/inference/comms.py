from asyncio import StreamReader, StreamWriter
import socket
from typing import Any
import msgpack
import struct

from ..logs import get_logger

logger = get_logger(__name__)

def _recv_exact(sock, content_size):
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
    msg_len_packed = _recv_exact(conn, 4)
    msg_len = struct.unpack('!I', msg_len_packed)[0]
    if not msg_len:
        return None

    msg_packed = _recv_exact(conn, msg_len)
    return msgpack.unpackb(msg_packed, raw=False)

def send_len_then_msg(conn: socket.socket, msg: dict[str, Any]):
    msg_packed = msgpack.packb(msg, use_bin_type=True)
    msg_len = len(msg_packed)
    msg_len_packed = struct.pack('!I', msg_len)  # 4-byte network byte order
    conn.sendall(msg_len_packed + msg_packed)

# *** ASYNC:

async def _recv_exact_async(reader: StreamReader, content_size) -> bytes | None:
    # does readexactly result in CancelledError bubbling up due to internal awaits?
    # PRN? timeout?
    return await reader.readexactly(content_size)

async def recv_len_then_msg_async(reader: StreamReader) -> dict[str, Any] | None:
    msg_len_packed = await _recv_exact_async(reader, 4)
    if msg_len_packed is None:
        logger.warn("recv_len_then_msg_async: msg_len_packed is None")
        return None
    msg_len = struct.unpack('!I', msg_len_packed)[0]
    if msg_len is None:
        logger.warn("recv_len_then_msg_async: msg_len is None")
        return None

    msg_packed = await _recv_exact_async(reader, msg_len)
    if msg_packed is None:
        logger.warn("recv_len_then_msg_async: msg_packed is None")
        return None
    return msgpack.unpackb(msg_packed, raw=False)

async def send_len_then_msg_async(writer: StreamWriter, msg: dict[str, Any]):
    msg_packed = msgpack.packb(msg, use_bin_type=True)
    msg_len = len(msg_packed)
    msg_len_packed = struct.pack('!I', msg_len)  # 4-byte network byte order
    # conn.sendall(msg_len_packed + msg_packed)
    writer.write(msg_len_packed + msg_packed)
    await writer.drain()  # TODO right way to wait?
