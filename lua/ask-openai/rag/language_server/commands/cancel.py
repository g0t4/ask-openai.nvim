from pygls.lsp.server import LanguageServer
from pygls.protocol.json_rpc import MsgId
from language_server.stoppers import request_stop
from logs import get_logger

logger = get_logger(__name__)

def setup(server: LanguageServer):
    original__handle_cancel_notification = server.protocol._handle_cancel_notification

    def _trigger_stopper_on_cancel(msg_id: MsgId):
        if request_stop(msg_id):
            logger.info(f'triggered stopper {msg_id=}')
            return

        # logger.info(f"fallback to original__handle_cancel_notification {msg_id}")
        original__handle_cancel_notification(msg_id)

    server.protocol._handle_cancel_notification = _trigger_stopper_on_cancel
