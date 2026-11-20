"""Плагины товаров: как разбирать загружаемый склад и как его выдавать."""

from .base import Plugin
from .gmail import GmailPlugin
from .text import TextPlugin

PLUGINS: dict[str, Plugin] = {p.key: p for p in (GmailPlugin(), TextPlugin())}


def get_plugin(key: str | None) -> Plugin:
    return PLUGINS.get(key or "", PLUGINS["text"])
