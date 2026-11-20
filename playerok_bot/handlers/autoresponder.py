"""Автоответчик: приветствие, команда !наличие, правила по ключевым словам."""

from __future__ import annotations

from aiogram import F, Router
from aiogram.fsm.context import FSMContext
from aiogram.types import CallbackQuery, Message

from db import db
from keyboards import BLUE, GREEN, back, btn, cancel, kb, toggle
from states import AutoReply

from .common import esc, get_engine, show

router = Router()


async def ar_menu(target) -> None:
    tg_id = target.from_user.id
    user = await db.get_user(tg_id)
    rules = await db.autoreplies(tg_id)
    lines = [
        "💬 <b>Автоответчик</b>\n",
        f"Статус: {'🟢 включён' if user['autoreply'] else '⚪️ выключен'}",
        f"👋 Приветствие новым покупателям: {'🟢' if user['greeting_on'] else '⚪️'}",
        f"<i>{esc((user['greeting_text'] or '')[:300])}</i>",
        f"📦 Команда <code>!наличие</code>: {'🟢' if user['stock_command'] else '⚪️'}\n",
        f"<b>Правила ({len(rules)}):</b>",
    ]
    if not rules:
        lines.append("Пока нет. Пример: «гарантия, как долго» → «Гарантия 24 часа».")
    for i, rule in enumerate(rules, 1):
        mode = "=" if rule["exact"] else "≈"
        lines.append(f"{i}. {mode} <code>{esc(rule['triggers'][:60])}</code> → {esc(rule['response'][:60])}")
    rows = [
        [toggle("Автоответчик", bool(user["autoreply"]), "ut:autoreply:ar")],
        [
            toggle("Приветствие", bool(user["greeting_on"]), "ut:greeting_on:ar"),
            toggle("!наличие", bool(user["stock_command"]), "ut:stock_command:ar"),
        ],
        [btn("✏️ Текст приветствия", "ar_greet", BLUE), btn("➕ Добавить правило", "ar_add", GREEN)],
    ]
    if rules:
        rows.append([btn("🗑 Удалить правило", "ar_dellist", BLUE)])
    rows.append(back())
    await show(target, "\n".join(lines), kb(rows))


@router.callback_query(F.data == "ar")
async def cb_ar(call: CallbackQuery, state: FSMContext) -> None:
    await state.clear()
    if await get_engine(call):
        await ar_menu(call)


@router.callback_query(F.data == "ar_greet")
async def cb_greet(call: CallbackQuery, state: FSMContext) -> None:
    await state.set_state(AutoReply.greeting)
    await show(
        call,
        "✏️ Отправьте текст приветствия.\nПеременная <code>{buyer}</code> — ник покупателя.\n\n"
        "Приветствие отправляется один раз — на первое сообщение в новом чате.",
        cancel("ar"),
    )


@router.message(AutoReply.greeting, F.text)
async def got_greet(message: Message, state: FSMContext) -> None:
    await db.set_user_field(message.from_user.id, "greeting_text", message.text[:1500])
    await state.clear()
    await message.answer("✅ Приветствие сохранено.")
    await ar_menu(message)


@router.callback_query(F.data == "ar_add")
async def cb_add(call: CallbackQuery, state: FSMContext) -> None:
    await state.set_state(AutoReply.triggers)
    await show(
        call,
        "➕ <b>Новое правило — шаг 1/2</b>\n\n"
        "Отправьте ключевые слова через запятую, например:\n<code>гарантия, как долго, сколько живёт</code>\n\n"
        "Бот ответит, если сообщение <b>содержит</b> любое из слов.\n"
        "Начните с <code>=</code>, чтобы требовать <b>точное</b> совпадение (например <code>=!помощь</code>).",
        cancel("ar"),
    )


@router.message(AutoReply.triggers, F.text)
async def got_triggers(message: Message, state: FSMContext) -> None:
    raw = message.text.strip()
    exact = raw.startswith("=")
    triggers = raw.lstrip("=").strip()
    if not triggers:
        await message.answer("Пустой список слов, попробуйте ещё раз.")
        return
    await state.update_data(triggers=triggers, exact=exact)
    await state.set_state(AutoReply.response)
    await message.answer(
        "➕ <b>Шаг 2/2</b>\nТеперь отправьте текст ответа. Можно использовать <code>{buyer}</code>.",
        reply_markup=cancel("ar"),
    )


@router.message(AutoReply.response, F.text)
async def got_response(message: Message, state: FSMContext) -> None:
    data = await state.get_data()
    await db.add_autoreply(message.from_user.id, data["triggers"], message.text[:1500], data["exact"])
    await state.clear()
    await message.answer("✅ Правило добавлено.")
    await ar_menu(message)


@router.callback_query(F.data == "ar_dellist")
async def cb_dellist(call: CallbackQuery) -> None:
    rules = await db.autoreplies(call.from_user.id)
    rows = [[btn(f"🗑 {i}. {r['triggers'][:40]}", f"ar_del:{r['id']}", BLUE)] for i, r in enumerate(rules, 1)]
    rows.append(back("ar"))
    await show(call, "Выберите правило для удаления:", kb(rows))


@router.callback_query(F.data.startswith("ar_del:"))
async def cb_del(call: CallbackQuery) -> None:
    await db.delete_autoreply(call.from_user.id, int(call.data.split(":")[1]))
    await call.answer("Удалено")
    await ar_menu(call)
