"""Точка входа: python bot.py"""

from __future__ import annotations

import asyncio
import logging

from aiogram import Bot, Dispatcher
from aiogram.client.default import DefaultBotProperties
from aiogram.enums import ParseMode
from aiogram.fsm.storage.memory import MemoryStorage
from aiogram.types import BotCommand

import config
from db import db
from engine import manager
from handlers import setup_routers
from handlers.common import AccessMiddleware

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)-7s | %(name)s: %(message)s",
)
logging.getLogger("httpx").setLevel(logging.WARNING)


async def main() -> None:
    await db.connect()
    bot = Bot(config.BOT_TOKEN, default=DefaultBotProperties(parse_mode=ParseMode.HTML))
    dp = Dispatcher(storage=MemoryStorage())
    dp.message.outer_middleware(AccessMiddleware())
    dp.callback_query.outer_middleware(AccessMiddleware())
    dp.include_router(setup_routers())

    manager.bot = bot
    await bot.set_my_commands(
        [BotCommand(command="start", description="Запуск / главное меню"),
         BotCommand(command="menu", description="Главное меню")]
    )
    me = await bot.get_me()
    logging.info("Бот @%s запущен", me.username)
    await manager.start_all()
    try:
        await dp.start_polling(bot, allowed_updates=dp.resolve_used_update_types())
    finally:
        await manager.stop_all()
        await db.close()
        await bot.session.close()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except (KeyboardInterrupt, SystemExit):
        pass
