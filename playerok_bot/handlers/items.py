"""Загрузка лотов с аккаунта Playerok и подключение их к боту."""

from __future__ import annotations

from aiogram import F, Router
from aiogram.types import CallbackQuery

from db import db
from keyboards import BLUE, GREEN, back, btn, kb
from plugins import PLUGINS

from .common import esc, get_engine, show

router = Router()

PAGE = 8
_cache: dict[int, list] = {}

STATUS = {
    "APPROVED": "🟢 активен",
    "SOLD": "💰 продан",
    "EXPIRED": "⌛️ истёк",
    "PENDING_MODERATION": "⏳ модерация",
    "PENDING_APPROVAL": "⏳ проверка",
    "DECLINED": "❌ отклонён",
    "BLOCKED": "🚫 заблокирован",
    "DRAFT": "📝 черновик",
    "DISCONTINUED": "⏸ снят",
    "REMOVED": "🗑 удалён",
}


def status_label(status) -> str:
    key = str(getattr(status, "value", status) or "")
    return STATUS.get(key, key or "—")


async def fetch_items(engine) -> list:
    items, after = [], None
    for _ in range(6):
        page = await engine.account.items.search(user_id=engine.me_id, first=24, after=after)
        items.extend(page)
        if not page.has_next_page or not page.end_cursor:
            break
        after = page.end_cursor
    return items


@router.callback_query(F.data.startswith("pk_items:") | F.data.startswith("pk_page:"))
async def cb_items(call: CallbackQuery) -> None:
    engine = await get_engine(call)
    if not engine:
        return
    tg_id = call.from_user.id
    fresh = call.data.startswith("pk_items:")
    page_num = int(call.data.split(":")[1])
    if fresh or tg_id not in _cache:
        await call.answer("⏳ Загружаю товары с Playerok…")
        try:
            _cache[tg_id] = await fetch_items(engine)
        except Exception as exc:
            await show(call, f"⚠️ Не удалось загрузить товары: <code>{esc(str(exc))[:300]}</code>", kb([back()]))
            return
    items = _cache[tg_id]
    if not items:
        await show(
            call,
            "📭 На аккаунте Playerok не найдено лотов.\nСоздайте лот на сайте и нажмите «Обновить».",
            kb([[btn("🔄 Обновить", "pk_items:0", GREEN)], back()]),
        )
        return

    connected = {p["item_id"] for p in await db.products(tg_id)}
    pages = (len(items) + PAGE - 1) // PAGE
    page_num = max(0, min(page_num, pages - 1))
    rows = []
    for item in items[page_num * PAGE : (page_num + 1) * PAGE]:
        mark = "✅ " if item.id in connected else ""
        name = (item.name or "Без названия")[:38]
        rows.append([btn(f"{mark}{name} · {item.price:g}₽", f"pki:{item.id}", GREEN if mark else BLUE)])
    nav = []
    if page_num > 0:
        nav.append(btn("◀️", f"pk_page:{page_num - 1}"))
    nav.append(btn(f"{page_num + 1}/{pages}", f"pk_page:{page_num}"))
    if page_num < pages - 1:
        nav.append(btn("▶️", f"pk_page:{page_num + 1}"))
    rows.append(nav)
    rows.append([btn("🔄 Обновить", "pk_items:0", GREEN), btn("⬅️ Меню", "menu")])
    await show(
        call,
        f"📥 <b>Ваши лоты на Playerok</b> ({len(items)})\n\n"
        "Выберите лот, чтобы подключить его к боту и управлять им.\n✅ — уже подключён.",
        kb(rows),
    )


@router.callback_query(F.data.startswith("pki:"))
async def cb_item(call: CallbackQuery) -> None:
    engine = await get_engine(call)
    if not engine:
        return
    item_id = call.data.split(":", 1)[1]
    item = next((i for i in _cache.get(call.from_user.id, []) if i.id == item_id), None)
    if item is None:
        try:
            item = await engine.account.items.get(item_id=item_id)
        except Exception as exc:
            await show(call, f"⚠️ Лот не найден: {esc(str(exc))[:200]}", kb([back("pk_items:0")]))
            return

    product = await db.product_by_item(call.from_user.id, item.id)
    game = item.game.name if item.game and item.game.name else "—"
    category = item.category.name if item.category and item.category.name else "—"
    link = f"https://playerok.com/products/{item.slug}" if item.slug else None
    text = (
        f"🛍 <b>{esc(item.name or '')}</b>\n\n"
        f"💵 Цена: <b>{item.price:g} ₽</b>\n"
        f"🎮 Игра: {esc(game)}\n"
        f"📂 Категория: {esc(category)}\n"
        f"📌 Статус: {status_label(item.status)}\n"
    )
    rows = []
    if product:
        text += "\n✅ Лот подключён к боту."
        rows.append([btn("⚙️ Управление товаром", f"prod:{product['id']}", GREEN)])
    else:
        text += "\nВыберите плагин, которым бот будет выдавать этот товар:"
        for plugin in PLUGINS.values():
            style = GREEN if plugin.key == "gmail" else BLUE
            rows.append([btn(f"{plugin.emoji} Подключить: {plugin.title}", f"pkc:{plugin.key}:{item.id}", style)])
    if link:
        rows.append([btn("🔗 Открыть на Playerok", url=link)])
    rows.append(back("pk_page:0", "⬅️ К списку"))
    await show(call, text, kb(rows))


@router.callback_query(F.data.startswith("pkc:"))
async def cb_connect_item(call: CallbackQuery) -> None:
    engine = await get_engine(call)
    if not engine:
        return
    _, plugin_key, item_id = call.data.split(":", 2)
    item = next((i for i in _cache.get(call.from_user.id, []) if i.id == item_id), None)
    if item is None:
        item = await engine.account.items.get(item_id=item_id)
    product_id = await db.add_product(
        call.from_user.id, item.id, item.slug, item.name or "Товар", item.price or 0, plugin_key
    )
    await call.answer("✅ Товар подключён!")
    from .products import product_card

    await product_card(call, product_id)
