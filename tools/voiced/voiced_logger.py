"""Logging helpers that write to ~/.local/state/ask-openai/voiced.log."""

from __future__ import annotations

import logging
from logging.handlers import RotatingFileHandler

from tools.voiced.config import log_path


def get_logger(name: str) -> logging.Logger:
    """Return a logger that appends to voiced.log (cached per name)."""
    logger = logging.getLogger(name)
    if logger.handlers:
        return logger

    logger.setLevel(logging.DEBUG)
    logger.propagate = False

    path = log_path()
    path.parent.mkdir(parents=True, exist_ok=True)

    handler = RotatingFileHandler(
        path,
        maxBytes=5 * 1024 * 1024,
        backupCount=3,
        encoding="utf-8",
    )
    handler.setFormatter(
        logging.Formatter("%(asctime)s %(levelname)-7s %(name)s: %(message)s")
    )
    logger.addHandler(handler)
    return logger

