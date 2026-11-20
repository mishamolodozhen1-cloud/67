"""Старт, подключение аккаунта Playerok по токену и главное меню."""

from __future__ import annotations

from aiogram import F, Router
from aiogram.filters import Command, CommandStart
from aiogram.fsm.context import FSMContext
from aiogram.types import CallbackQuery, Message
from PlayerokAPI import Account, UnauthorizedError

import config
from db import db
from engine import manager
from keyboards import GREEN, back, btn, cancel, connect_menu, kb, main_menu
from states import Connect

from .common import esc, get_engine, show

router = Router()

WELCOME = (
    "👋 <b>Playerok Sales Bot</b>\n\n"
    "Автоматизация продаж на Playerok:\n"
    "• ⚡️ автовыдача товара сразу после оплаты\n"
    "• 📧 плагин <b>Gmail аккаунты</b> — поштучно или пачкой за одну оплату\n"
    "• 📥 загрузка ваших лотов прямо с Playerok\n"
    "• 💬 автоответчик, приветствие, команда !наличие\n"
    "• 🔔 уведомления о сообщениях и продажах с ответом из Telegram\n\n"
    "Чтобы начать, подключите аккаунт Playerok через токен 👇"
)

TOKEN_HELP = (
    "🔑 <b>Где взять токен Playerok</b>\n\n"
    "1. Войдите в аккаунт на <b>playerok.com</b> в браузере на компьютере.\n"
    "2. Нажмите <b>F12</b> → вкладка <b>Application</b> (Приложение).\n"
    "3. Слева <b>Cookies</b> → <code>https://playerok.com</code>.\n"
    "4. Найдите cookie <code>token</code> и скопируйте его значение.\n\n"
    "⚠️ Никому не передавайте токен — это полный доступ к аккаунту. "
    "Сообщение с токеном бот удалит сразу после проверки."
)


async def menu_text(tg_id: int) -> str:
    user = await db.get_user(tg_id)
    engine = manager.get(tg_id)
    products = await db.products(tg_id)
    stock = sum(p["stock_count"] for p in products)
    balance = "—"
    if engine:
        try:
            bal = await engine.account.get_balance()
            balance = f"{bal.available:g} ₽"
        except Exception:
            pass
    status = engine.status if engine else "🔴 не запущен"
    return (
        "🏠 <b>Главное меню</b>\n\n"
        f"👤 Аккаунт: <b>{esc(user['pk_username'] or '—')}</b>\n"
        f"💰 Баланс: <b>{balance}</b>\n"
        f"⚙️ Автоматизация: {status}\n"
        f"⚡️ Автовыдача: {'🟢 вкл' if user['auto_delivery'] else '⚪️ выкл'}\n"
        f"📦 Товаров в боте: <b>{len(products)}</b>, единиц на складе: <b>{stock}</b>"
    )


async def open_menu(target: Message | CallbackQuery, state: FSMContext | None = None) -> None:
    if state:
        await state.clear()
    if not await get_engine(target):
        return
    await show(target, await menu_text(target.from_user.id), main_menu())


@router.message(CommandStart())
async def cmd_start(message: Message, state: FSMContext) -> None:
    await state.clear()
    user = await db.get_user(message.from_user.id)
    if user and user["token"]:
        await open_menu(message)
    else:
        await message.answer(WELCOME, reply_markup=connect_menu())


@router.message(Command("menu"))
async def cmd_menu(message: Message, state: FSMContext) -> None:
    await open_menu(message, state)


@router.callback_query(F.data == "menu")
async def cb_menu(call: CallbackQuery, state: FSMContext) -> None:
    await open_menu(call, state)


@router.callback_query(F.data == "token_help")
async def cb_token_help(call: CallbackQuery) -> None:
    await show(call, TOKEN_HELP, kb([[btn("🔑 Подключить Playerok", "connect", GREEN)], back("start")]))


@router.callback_query(F.data == "start")
async def cb_start(call: CallbackQuery, state: FSMContext) -> None:
    await state.clear()
    await show(call, WELCOME, connect_menu())


@router.callback_query(F.data == "connect")
async def cb_connect(call: CallbackQuery, state: FSMContext) -> None:
    await state.set_state(Connect.token)
    await show(
        call,
        "🔑 Отправьте сюда <b>токен</b> вашего аккаунта Playerok (значение cookie <code>token</code>).",
        kb([[btn("❓ Где взять токен", "token_help")], [btn("✖️ Отмена", "start")]]),
    )


@router.message(Connect.token, F.text)
async def got_token(message: Message, state: FSMContext) -> None:
    token = message.text.strip().strip('"').strip()
    if token.lower().startswith("token="):
        token = token[6:]
    try:
        await message.delete()
    except Exception:
        pass
    wait = await message.answer("⏳ Проверяю токен…")
    try:
        async with Account(token, proxy=config.PLAYEROK_PROXY) as acc:
            me = await acc.get_me()
    except UnauthorizedError:
        await wait.edit_text(
            "❌ Токен не подошёл (401). Проверьте, что скопировали значение cookie <code>token</code> полностью, "
            "и отправьте ещё раз.",
            reply_markup=cancel("start"),
        )
        return
    except Exception as exc:
        await wait.edit_text(
            f"⚠️ Не удалось проверить токен: <code>{esc(str(exc))[:300]}</code>\nПопробуйте ещё раз.",
            reply_markup=cancel("start"),
        )
        return

    await db.save_token(message.from_user.id, token, me.id, me.username or "")
    await state.clear()
    try:
        await manager.start(message.from_user.id, token)
    except Exception as exc:
        await wait.edit_text(f"⚠️ Токен верный, но движок не запустился: {esc(str(exc))[:300]}")
        return
    await wait.edit_text(
        f"✅ Аккаунт <b>{esc(me.username or me.id)}</b> подключён!\n\n"
        "Дальше: нажмите <b>📥 Загрузить с Playerok</b>, выберите лот и подключите к нему "
        "плагин (например, Gmail аккаунты), затем загрузите наличие.",
    )
    await open_menu(message)
