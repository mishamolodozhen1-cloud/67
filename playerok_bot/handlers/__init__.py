from aiogram import Router

from . import autoresponder, deals, items, products, settings, start


def setup_routers() -> Router:
    root = Router()
    for module in (start, items, products, autoresponder, deals, settings):
        root.include_router(module.router)
    return root
