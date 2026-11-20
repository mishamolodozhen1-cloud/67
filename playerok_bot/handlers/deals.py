"""Сделки, статистика, баланс, ответ покупателю из Telegram."""

from __future__ import annotations

import datetime as dt

from aiogram import F, Router
from aiogram.fsm.context import FSMContext
from aiogram.types import CallbackQuery, Message

from db import db
from keyboards import BLUE, GREEN, back, btn, cancel, kb
from states import Reply

from .common import esc, get_engine, show

router = Router()

BOT_STATUS = {
    "delivered": "✅ выдано",
    "no_stock": "❗️ нет товара",
    "error": "⚠️ ошибка",
    "manual": "✋ вручную",
    "old": "🕓 до подключения",
    "refund": "↩️ возврат",
}
PK_STATUS = {
    "PENDING": "⏳ ожидает оплаты",
    "PAID": "💸 оплачена",
    "SENT": "📨 отправлена",
    "CONFIRMED": "✅ подтверждена",
    "ROLLED_BACK": "↩️ возврат",
    "FAILED": "❌ не удалась",
}


def _fmt_time(ts: float | None) -> str:
    if not ts:
        return ""
    return dt.datetime.fromtimestamp(ts).strftime("%d.%m %H:%M")


@router.callback_query(F.data == "deals")
async def cb_deals(call: CallbackQuery) -> None:
    if not await get_engine(call):
        return
    deals = await db.recent_deals(call.from_user.id, 15)
    lines = ["🤝 <b>Сделки, обработанные ботом</b>\n"]
    rows = []
    for d in deals:
        status = BOT_STATUS.get(d["status"], d["status"])
        lines.append(
            f"{_fmt_time(d['created_at'])} · {status} · {esc((d['item_name'] or '')[:30])} · "
            f"{esc(d['buyer'] or '')} · {d['amount'] or 0:g}₽"
        )
        if d["status"] in ("no_stock", "error", "manual"):
            rows.append([btn(f"🔁 Выдать: {(d['item_name'] or '')[:25]} ({d['buyer']})", f"redeliver:{d['deal_id']}", GREEN)])
    if not deals:
        lines.append("Пока пусто — как только придёт оплата, сделка появится здесь.")
    rows.append([btn("🌐 Сделки с Playerok", "pk_deals", BLUE)])
    rows.append(back())
    await show(call, "\n".join(lines), kb(rows[:12] if len(rows) > 12 else rows))


@router.callback_query(F.data == "pk_deals")
async def cb_pk_deals(call: CallbackQuery) -> None:
    engine = await get_engine(call)
    if not engine:
        return
    await call.answer("⏳ Загружаю…")
    try:
        page = await engine.account.deals.search(filter={"direction": "OUT"}, first=15)
    except Exception:
        try:
            page = await engine.account.deals.search(filter={"userId": engine.me_id}, first=15)
        except Exception as exc:
            await show(call, f"⚠️ Не удалось получить сделки: {esc(str(exc))[:300]}", kb([back("deals")]))
            return
    lines = ["🌐 <b>Последние продажи на Playerok</b>\n"]
    rows = []
    for d in page:
        status = str(getattr(d.status, "value", d.status) or "")
        name = d.item.name if d.item and d.item.name else "товар"
        buyer = d.user.username if d.user and d.user.username else "—"
        when = d.created_at.strftime("%d.%m %H:%M") if d.created_at else ""
        price = d.item.price if d.item else 0
        lines.append(f"{when} · {PK_STATUS.get(status, status)} · {esc(name[:30])} · {esc(buyer)} · {price:g}₽")
        if status == "PAID":
            rows.append([btn(f"📤 Выдать: {name[:25]} ({buyer})", f"redeliver:{d.id}", GREEN)])
    if not list(page):
        lines.append("Сделок нет.")
    rows.append([btn("🔄 Обновить", "pk_deals", GREEN), btn("⬅️ Назад", "deals")])
    await show(call, "\n".join(lines), kb(rows))


@router.callback_query(F.data.startswith("redeliver:"))
async def cb_redeliver(call: CallbackQuery) -> None:
    engine = await get_engine(call)
    if not engine:
        return
    deal_id = call.data.split(":", 1)[1]
    await call.answer("⏳ Выдаю…")
    try:
        result = await engine.redeliver(deal_id)
    except Exception as exc:
        result = f"ошибка: {exc}"
    text = {
        "delivered": "✅ Товар выдан покупателю.",
        "no_stock": "❗️ Не хватает товара на складе — пополните его.",
        "manual": "✋ Лот не подключён к боту или автовыдача выключена.",
    }.get(result, f"Результат: {result}")
    await call.message.answer(text, reply_markup=kb([back("deals", "🤝 К сделкам")]))


@router.callback_query(F.data == "stats")
async def cb_stats(call: CallbackQuery) -> None:
    if not await get_engine(call):
        return
    s = await db.stats(call.from_user.id)
    products = await db.products(call.from_user.id)
    lines = [
        "📊 <b>Статистика автопродаж</b>\n",
        f"Сегодня (24ч): <b>{s['today']['n']}</b> продаж на <b>{s['today']['s']:g} ₽</b>",
        f"Всего: <b>{s['total']['n']}</b> продаж на <b>{s['total']['s']:g} ₽</b>",
        f"Выдано единиц товара: <b>{s['total']['q']}</b>",
        f"Проблемных сделок: <b>{s['failed']}</b>\n",
        "<b>По товарам:</b>",
    ]
    for p in products:
        lines.append(f"• {esc(p['name'][:35])}: продано {p['sold_count']}, на складе {p['stock_count']}")
    if not products:
        lines.append("—")
    await show(call, "\n".join(lines), kb([[btn("🔄 Обновить", "stats", GREEN)], back()]))


@router.callback_query(F.data == "balance")
async def cb_balance(call: CallbackQuery) -> None:
    engine = await get_engine(call)
    if not engine:
        return
    try:
        b = await engine.account.get_balance()
    except Exception as exc:
        await show(call, f"⚠️ Не удалось получить баланс: {esc(str(exc))[:300]}", kb([back()]))
        return
    await show(
        call,
        "💰 <b>Баланс Playerok</b>\n\n"
        f"Доступно: <b>{b.available:g} ₽</b>\n"
        f"Заморожено: <b>{b.frozen:g} ₽</b>\n"
        f"Ожидает зачисления: <b>{b.pending_income:g} ₽</b>\n"
        f"Можно вывести: <b>{b.withdrawable:g} ₽</b>\n"
        f"Всего: <b>{b.value:g} ₽</b>",
        kb([[btn("🔄 Обновить", "balance", GREEN)], back()]),
    )


# --- ответ покупателю -----------------------------------------------------------


@router.callback_query(F.data.startswith("rp:"))
async def cb_reply(call: CallbackQuery, state: FSMContext) -> None:
    chat_id = call.data.split(":", 1)[1]
    await state.set_state(Reply.text)
    await state.update_data(chat_id=chat_id)
    await call.message.answer("✍️ Напишите ответ покупателю — он уйдёт в чат Playerok:", reply_markup=cancel("menu"))
    await call.answer()


@router.message(Reply.text, F.text)
async def got_reply(message: Message, state: FSMContext) -> None:
    engine = await get_engine(message)
    if not engine:
        return
    chat_id = (await state.get_data()).get("chat_id")
    await state.clear()
    try:
        await engine.send_chat(chat_id, message.text)
    except Exception as exc:
        await message.answer(f"⚠️ Не отправлено: <code>{esc(str(exc))[:300]}</code>")
        return
    await message.answer(
        "✅ Отправлено.",
        reply_markup=kb([[btn("✍️ Ещё ответ", f"rp:{chat_id}", GREEN), btn("🏠 Меню", "menu")]]),
    )
