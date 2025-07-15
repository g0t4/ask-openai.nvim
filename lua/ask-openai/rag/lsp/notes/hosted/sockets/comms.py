import msgpack
import struct

def recv_exact(sock, content_size):
    buf = b''
    while len(buf) < content_size:
        chunk = sock.recv(content_size - len(buf))
        if not chunk:
            raise ConnectionError("Socket connection closed")
        buf += chunk
    return buf

def recv_len_then_msg(conn):
    print("receiving...")
    rx_msg_len_packed = recv_exact(conn, 4)
    print(f'{rx_msg_len_packed=}')
    rx_msg_len = struct.unpack('!I', rx_msg_len_packed)[0]
    print(f'{rx_msg_len=}')
    if not rx_msg_len:
        return

    rx_msg_packed = recv_exact(conn, rx_msg_len)
    rx_msg = msgpack.unpackb(rx_msg_packed, raw=False)

    return rx_msg
