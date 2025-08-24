# asyncio.Event()
#

import asyncio
from pygls.protocol.json_rpc import MsgId

stoppers: dict[MsgId, asyncio.Event] = {}

def add_stopper(msg_id):
    stopper = asyncio.Event()
    stoppers[msg_id] = stopper
    return stopper

def request_stop(msg_id):
    stopper = stoppers.get(msg_id, None)
    if stopper is None:
        raise ValueError(f"missing stopper for {msg_id=}")

    stopper.set()

def remove_stopper(msg_id):
    if msg_id in stoppers:
        del stoppers[msg_id]
