import asyncio
from pygls.lsp.server import LanguageServer

from language_server.stoppers import create_stopper, remove_stopper
from logs import get_logger


def setup(server: LanguageServer):

    @server.command("SLEEPY")
    async def sleepy(_ls: LanguageServer, args: dict):
        msg_id = _ls.protocol.msg_id  # workaround to load msg_id via contextvars
        logger.info(f"sleepy started {msg_id=}")
        stopper = create_stopper(msg_id)

        try:
            for i in range(10):
                stopper.throw_if_stopped()

                async with asyncio.TaskGroup() as tg:
                    job = tg.create_task(asyncio.sleep(3))
                    stop_requested = tg.create_task(stopper.wait())
                    done, pending = await asyncio.wait(
                        [job, stop_requested],
                        return_when=asyncio.FIRST_COMPLETED,
                    )
                    if stop_requested in done:
                        # Raising inside the TG cancels/awaits other tasks
                        stopper.throw_if_stopped()

                    stop_requested.cancel()  # cleanup

                logger.info(f"ping {msg_id=} {i}")

            return {"status": "done", "msg_id": msg_id}
        except asyncio.CancelledError as e:
            logger.info(f"KILLED {msg_id=}")  #, exc_info=e)
            return {"status": "canelled", "msg_id": msg_id}
        finally:
            remove_stopper(msg_id)
