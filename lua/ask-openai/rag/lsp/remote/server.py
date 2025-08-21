#
# z rag
# time python3 -m lsp.notes.hosted.sockets.server

print('imports...')

import logging
import socket
import signal
import sys
import rich

from lsp.remote import qwen3_embeddings, qwen3_rerank
from lsp.logs import Timer, get_logger, logging_fwk_to_console
from .comms import *

print('imports done')

# * command line args
verbose = "--verbose" in sys.argv or "--debug" in sys.argv
info = "--info" in sys.argv

level = logging.DEBUG if verbose else (logging.INFO if info else logging.WARNING)
logging_fwk_to_console(level)
logger = get_logger(__name__)

print('testing known embeddings...')
qwen3_embeddings.test_known_embeddings()

print('opening socket')

listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
# set REUSEADDR so TIME-WAIT ports don't block restarting server, else wait upwards of a minute
listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)

listener.bind(("0.0.0.0", 8015))
listener.listen()

clear_iterm_scrolback = "\x1b]1337;ClearScrollback\a"
print(clear_iterm_scrolback)
rich.print("[green bold]Server ready...")

def signal_handler(sig, frame):
    print('You pressed Ctrl+C!')
    listener.close()
    exit(0)

signal.signal(signal.SIGINT, signal_handler)

# listener.settimeout(60) # PRN for timeout on listener.accept(), but I don't need that if all I do is wait for a single connection

def handle():
    conn.settimeout(10)  # give client 10 seconds max to send/recv its data

    rx_msg = recv_len_then_msg(conn)
    if not rx_msg:
        conn.close()
        return

    rx_type = rx_msg['type']

    with Timer() as encode_timer:
        if rx_type == 'embed':
            texts = rx_msg['texts']
            embeddings, input_ids = qwen3_embeddings.encode(texts)
            tx_msg = {'embeddings': embeddings.tolist()}

            def after_send():
                rich.print(f"[blue]encoded {input_ids.shape[0]} sequences of {input_ids.shape[1]} tokens in {encode_timer.elapsed_ms():.3f} ms")
                dump_token_details(input_ids, texts)

        elif rx_type == 'rerank':
            query = rx_msg['query']
            docs = rx_msg['docs']
            scores = qwen3_rerank.rerank_semantic_grep(query, docs)
            tx_msg = {'scores': scores}

            def after_send():
                pass

        else:
            raise ValueError(f'unsupported {rx_type=}')

    send_len_then_msg(conn, tx_msg)
    conn.close()

    if rx_type == 'embed':
        after_send()

def dump_token_details(input_ids, input_texts):
    if not logger.isEnabledFor(logging.DEBUG):
        return

    total_actual_tokens = 0
    biggest = 0
    for t in input_texts:
        current = len(t)
        total_actual_tokens += current
        if current > biggest:
            biggest = current
        rich.print(f"  {current}: {t}")

    avg_tokens = total_actual_tokens / len(input_texts)
    rich.print(f"  avg_tokens={avg_tokens:.2f} longest={biggest}")

    # PRN move this into encoder logic and validate the numbers using attention mask
    wasted_tokens_percent = 100 * (biggest - avg_tokens) / biggest
    rich.print(f"  wasted_tokens={wasted_tokens_percent:.2f}%")

    logger.debug(f"  input_ids={input_ids.tolist()}")

while True:
    try:
        conn, _ = listener.accept()
    except socket.timeout:
        # FYI can do periodic work here, differentiates socket(listener) level timeout vs connection (handled below)
        continue
    except Exception:
        logger.exception("accept() failed")
        continue

    try:
        handle()
    except socket.timeout:
        # FYI can do periodic work here too (i.e. could unload model if not used in last X minutes) => would need to call listener.settimeout
        logger.warning("connection (i.e. recv/send) timeout")
    except Exception:
        logger.exception("handle() unhandled exception")
    finally:
        conn.close()
