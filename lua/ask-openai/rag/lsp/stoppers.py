# asyncio.Event()
#

import asyncio
from pygls.protocol.json_rpc import MsgId

class Stopper(asyncio.Event):

    def __init__(self, msg_id):
        super().__init__()
        self.msg_id = msg_id

    def request_stop(self):
        self.set()

    def throw_if_stopped(self):
        if self.is_set():
            raise asyncio.CancelledError(f"cooperative cancel {self.msg_id=}")

stoppers: dict[MsgId, Stopper] = {}

def create_stopper(msg_id) -> Stopper:
    stopper = Stopper(msg_id)
    stoppers[msg_id] = stopper
    return stopper

def request_stop(msg_id) -> bool:
    stopper = stoppers.get(msg_id, None)
    if stopper is None:
        return False

    stopper.request_stop()
    return True

def remove_stopper(msg_id):
    if msg_id in stoppers:
        del stoppers[msg_id]
