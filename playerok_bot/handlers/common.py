"""Общие помощники для обработчиков."""

from __future__ import annotations

import html
import logging
from typing import Any, Awaitable, Callable

from aiogram import BaseMiddleware
from aiogram.exceptions import TelegramBadRequest
from aiogram.types import CallbackQuery, InlineKeyboardMarkup, Message, TelegramObject

import config
from db import db
from engine import Engine, manager
from keyboards import connect_menu

log = logging.getLogger("handlers")

esc = html.escape


class AccessMiddleware(BaseMiddleware):
    """Пускает только OWNER_IDS, если список задан."""

    async def __call__(
        self,
        handler: Callable[[TelegramObject, dict[str, Any]], Awaitable[Any]],
        event: TelegramObject,
        data: dict[str, Any],
    ) -> Any:
        user = data.get("event_from_user")
        if config.OWNER_IDS and (user is None or user.id not in config.OWNER_IDS):
            if isinstance(event, Message):
                await event.answer("⛔️ Доступ к боту закрыт.")
            elif isinstance(event, CallbackQuery):
                await event.answer("⛔️ Доступ закрыт", show_alert=True)
            return None
        return await handler(event, data)


async def show(
    target: Message | CallbackQuery, text: str, markup: InlineKeyboardMarkup | None = None
) -> None:
    """Отредактировать сообщение с меню (для кнопок) или прислать новое."""
    if isinstance(target, CallbackQuery):
        msg = target.message
        try:
            if msg and msg.text is not None:
                await msg.edit_text(text, reply_markup=markup, disable_web_page_preview=True)
            else:
                await target.bot.send_message(
                    target.from_user.id, text, reply_markup=markup, disable_web_page_preview=True
                )
        except TelegramBadRequest as exc:
            if "not modified" not in str(exc):
                await target.bot.send_message(
                    target.from_user.id, text, reply_markup=markup, disable_web_page_preview=True
                )
        try:
            await target.answer()
        except TelegramBadRequest:
            pass
    else:
        await target.answer(text, reply_markup=markup, disable_web_page_preview=True)


async def get_engine(target: Message | CallbackQuery) -> Engine | None:
    """Движок пользователя; если аккаунт не подключён — предлагает подключить."""
    tg_id = target.from_user.id
    engine = manager.get(tg_id)
    if engine:
        return engine
    user = await db.get_user(tg_id)
    if user and user["token"]:
        try:
            return await manager.start(tg_id, user["token"])
        except Exception as exc:
            log.warning("Перезапуск движка %s не удался: %s", tg_id, exc)
            await show(
                target,
                f"⚠️ Не удалось подключиться к Playerok:\n<code>{esc(str(exc))[:300]}</code>\n\n"
                "Проверьте токен или попробуйте позже.",
                connect_menu(),
            )
            return None
    await show(target, "🔒 Сначала подключите аккаунт Playerok.", connect_menu())
    return None


def plural(n: int, one: str, few: str, many: str) -> str:
    n = abs(n)
    if n % 10 == 1 and n % 100 != 11:
        return one
    if 2 <= n % 10 <= 4 and not 12 <= n % 100 <= 14:
        return few
    return many
