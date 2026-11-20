"""Общие настройки и отключение аккаунта."""

from __future__ import annotations

from aiogram import F, Router
from aiogram.fsm.context import FSMContext
from aiogram.types import CallbackQuery, Message

from db import USER_TOGGLES, db
from engine import manager
from keyboards import BLUE, GREEN, back, btn, cancel, connect_menu, kb, toggle
from states import Settings

from .common import esc, get_engine, show

router = Router()


async def settings_menu(target) -> None:
    user = await db.get_user(target.from_user.id)
    engine = manager.get(target.from_user.id)
    text = (
        "⚙️ <b>Настройки</b>\n\n"
        f"👤 Аккаунт Playerok: <b>{esc(user['pk_username'] or '—')}</b>\n"
        f"⚙️ Движок: {engine.status if engine else '🔴 не запущен'}\n\n"
        "⚡️ <b>Автовыдача</b> — выдавать товар сразу после оплаты.\n"
        "📨 <b>Авто-«Отправлено»</b> — после выдачи отмечать сделку выполненной со стороны продавца.\n"
        f"⚠️ <b>Порог «мало товара»</b>: предупреждать, когда осталось ≤ {user['low_stock']} продаж."
    )
    rows = [
        [toggle("Автовыдача", bool(user["auto_delivery"]), "ut:auto_delivery:settings")],
        [toggle("Авто-«Отправлено»", bool(user["auto_complete"]), "ut:auto_complete:settings")],
        [
            toggle("🔔 Сообщения", bool(user["notify_messages"]), "ut:notify_messages:settings"),
            toggle("🔔 Продажи", bool(user["notify_deals"]), "ut:notify_deals:settings"),
        ],
        [btn(f"⚠️ Порог: {user['low_stock']}", "low_stock", BLUE), btn("♻️ Перезапуск", "restart", GREEN)],
        [btn("🔑 Сменить токен", "connect", BLUE), btn("🚪 Отключить аккаунт", "logout", BLUE)],
        back(),
    ]
    await show(target, text, kb(rows))


@router.callback_query(F.data == "settings")
async def cb_settings(call: CallbackQuery, state: FSMContext) -> None:
    await state.clear()
    if await get_engine(call):
        await settings_menu(call)


@router.callback_query(F.data.startswith("ut:"))
async def cb_user_toggle(call: CallbackQuery) -> None:
    _, field, back_to = call.data.split(":")
    if field not in USER_TOGGLES:
        await call.answer()
        return
    await db.toggle_user(call.from_user.id, field)
    if back_to == "ar":
        from .autoresponder import ar_menu

        await ar_menu(call)
    else:
        await settings_menu(call)


@router.callback_query(F.data == "low_stock")
async def cb_low_stock(call: CallbackQuery, state: FSMContext) -> None:
    await state.set_state(Settings.low_stock)
    await show(call, "Отправьте число: при скольких оставшихся продажах предупреждать (0 — не предупреждать).", cancel("settings"))


@router.message(Settings.low_stock, F.text)
async def got_low_stock(message: Message, state: FSMContext) -> None:
    if not message.text.strip().isdigit():
        await message.answer("Нужно целое число.")
        return
    await db.set_user_field(message.from_user.id, "low_stock", int(message.text.strip()))
    await state.clear()
    await settings_menu(message)


@router.callback_query(F.data == "restart")
async def cb_restart(call: CallbackQuery) -> None:
    user = await db.get_user(call.from_user.id)
    try:
        await manager.start(call.from_user.id, user["token"])
        await call.answer("♻️ Перезапущено", show_alert=False)
    except Exception as exc:
        await call.answer(f"Ошибка: {str(exc)[:150]}", show_alert=True)
    await settings_menu(call)


@router.callback_query(F.data == "logout")
async def cb_logout(call: CallbackQuery) -> None:
    await show(
        call,
        "🚪 Отключить аккаунт Playerok от бота?\nАвтовыдача и автоответчик перестанут работать. "
        "Товары и склад сохранятся.",
        kb([[btn("✅ Да, отключить", "logout_ok", GREEN), btn("✖️ Отмена", "settings")]]),
    )


@router.callback_query(F.data == "logout_ok")
async def cb_logout_ok(call: CallbackQuery) -> None:
    await manager.stop(call.from_user.id)
    await db.logout(call.from_user.id)
    await show(call, "✅ Аккаунт отключён. Подключите его снова, когда понадобится.", connect_menu())
