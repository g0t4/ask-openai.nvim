import msgpack
import struct
from lsp.logs import get_logger

logger = get_logger(__name__)

def recv_exact(sock, content_size):
    buf = b''
    while len(buf) < content_size:
        chunk = sock.recv(content_size - len(buf))
        if not chunk:
            raise ConnectionError("Socket connection closed")
        buf += chunk
    return buf

def recv_len_then_msg(conn):
    msg_len_packed = recv_exact(conn, 4)
    msg_len = struct.unpack('!I', msg_len_packed)[0]
    logger.debug(f'{msg_len=}')
    if not msg_len:
        return

    msg_packed = recv_exact(conn, msg_len)
    return msgpack.unpackb(msg_packed, raw=False)

def send_len_then_msg(conn, msg):
    msg_packed = msgpack.packb(msg, use_bin_type=True)
    msg_len = len(msg_packed)
    logger.debug(f'{msg_len=}')
    msg_len_packed = struct.pack('!I', msg_len)  # 4-byte network byte order
    conn.sendall(msg_len_packed + msg_packed)
