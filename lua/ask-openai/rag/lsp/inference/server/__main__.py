#
# z rag
# time python3 -m lsp.notes.hosted.sockets.server

print('imports starting...')

import asyncio
import logging
import rich
import signal
import socket
import sys

from . import qwen3_embeddings, qwen3_rerank
from lsp.logs import Timer, get_logger, logging_fwk_to_console
from ..comms import recv_len_then_msg_async, send_len_then_msg_async

print('imports done')

# * command line args
verbose = "--verbose" in sys.argv or "--debug" in sys.argv
info = "--info" in sys.argv

level = logging.DEBUG if verbose else (logging.INFO if info else logging.WARNING)
logging_fwk_to_console(level)
logger = get_logger(__name__)

def clear_iterm_scrollback():
    clear_iterm_scrolback = "\x1b]1337;ClearScrollback\a"
    print(clear_iterm_scrolback)

def colorful_ms(ms: float) -> str:
    if ms < 20:
        color = "green"
    elif ms > 100:
        color = "red"
    else:
        color = "yellow"
    return f"[{color}]{ms:.2f} ms[/]"

def dump_token_details(input_ids, input_texts):
    if not logger.isEnabledFor(logging.DEBUG):
        return

    # PRN async for log delays?

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

def enable_keepalive(writer: asyncio.StreamWriter):
    # for py3.12 and older, keep alive must be set on socket level
    sock = writer.get_extra_info("socket")
    if sock is None:
        raise Exception("Failed to get socket to set keep alive, aborting")

    sock.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
    # FYI socket options: https://www.man7.org/linux/man-pages/man7/socket.7.html

    try:
        # TODO research what values I should use here... mostly suggested to me and not yet vetted
        sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_KEEPIDLE, 30)
        sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_KEEPINTVL, 10)
        sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_KEEPCNT, 3)
    except AttributeError as e:
        logger.warning(f"Failed to set KEEP ALIVE socket options, will try to set on transport level {e}")

async def disconnect(writer):
    writer.close()
    await writer.wait_closed()

async def on_client_connected(reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
    logger.info("client connected")
    # PRN consider longer lived (i.e. all request batches for one round of semantic_grep)

    enable_keepalive(writer)

    # TODO pass timeout values to read/drain?
    request = await recv_len_then_msg_async(reader)
    if request is None:
        logger.warning("empty request, disconnecting")
        return await disconnect(writer)

    request_type = request['type']

    def after_send():
        pass

    with Timer() as encode_timer:
        # PRN split out this section to a socket agnostic dispatcher
        if request_type == 'embed':
            texts = request['texts']
            # PRN async encode?... really all I want async for is in the LSP to cancel pending buf_requests... this server side was just practice for asyncifying socket
            embeddings, input_ids = qwen3_embeddings.encode(texts)
            response = {'embeddings': embeddings.tolist()}

            def after_send():
                num_sequences = len(input_ids)
                num_tokens = len(input_ids[0])
                rich.print(f"[blue]embedded {num_sequences} sequences of {num_tokens} tokens in {colorful_ms(encode_elapsed_ms)} ms")
                dump_token_details(input_ids, texts)

        elif request_type == 'rerank':
            instruct: str = request['instruct']
            query: str = request['query']
            docs: list[str] = request['docs']
            # PRN async rerank?
            scores, input_ids = qwen3_rerank.rerank(instruct, query, docs)
            response = {'scores': scores}

            def after_send():
                num_docs = len(docs)
                num_tokens = len(input_ids[0])
                rich.print(f"[blue]re-ranked {num_docs} docs of {num_tokens=} tokens in {colorful_ms(encode_elapsed_ms)} ms")

        # PRN combine encode and rerank! do batches of both! and can abort between too

        else:
            logger.error(f'unsupported {request_type=}')
            return await disconnect(writer)

    encode_elapsed_ms = encode_timer.elapsed_ms()

    await send_len_then_msg_async(writer, response)
    await disconnect(writer)

    after_send()

async def main():

    logger.info('testing known embeddings in-process before server start...')
    qwen3_embeddings.test_known_embeddings_in_process()

    print('starting server socket')
    server = await asyncio.start_server(
        on_client_connected,
        host="0.0.0.0",
        port=8015,
        family=socket.AF_INET,

        # set REUSEADDR so TIME-WAIT ports don't block restarting server, else wait upwards of a minute
        reuse_address=True,  # default=True on *nix
        # reuse_port=True ... default=false, use this for load balancing though batching is gonna be a first fix for parallelism

        # py 3.13 has new arg but how about just set it socket level so you don't have to change if you change py version?
        # keep_alive=True  # since connections are long-lived from LSP, this can help with zombie client connections (close them down when heartbeat fails)
        #   will help when I move to long-lived connections across requests where it's not just one request/response per connection
    )

    clear_iterm_scrollback()

    addrs = ', '.join(str(sock.getsockname()) for sock in server.sockets)
    rich.print(f"[green bold]Server ready on {addrs}...")

    loop = asyncio.get_running_loop()
    stop = asyncio.Event()

    def graceful_stop(message):
        rich.print("[red bold] " + message + "\n  Shutting down server...")
        stop.set()

    # adding signal handler via loop means the handler can interact with the event loop (unlike using signal.signal())
    loop.add_signal_handler(signal.SIGINT, graceful_stop, f"received signal SIGINT - Ctrl-C")
    loop.add_signal_handler(signal.SIGTERM, graceful_stop, f"received signal SIGTERM")

    async with server:
        await stop.wait()

        # PRN cancel/close open connections to shutdown.. with short lived, connection per request, this is not as important
        # PRN does async context manager call close when leaving the "async with" block?
        server.close()
        await server.wait_closed()

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass  # extra guard
