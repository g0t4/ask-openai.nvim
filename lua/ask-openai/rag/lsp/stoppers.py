# asyncio.Event()
#

import asyncio
from pygls.protocol.json_rpc import MsgId

stoppers: dict[MsgId, asyncio.Event] = {}

def add_stopper(msg_id) -> asyncio.Event:
    stopper = asyncio.Event()
    stoppers[msg_id] = stopper
    return stopper

def request_stop(msg_id) -> bool:
    stopper = stoppers.get(msg_id, None)
    if stopper is None:
        return False

    stopper.set()
    return True

def remove_stopper(msg_id):
    if msg_id in stoppers:
        del stoppers[msg_id]
