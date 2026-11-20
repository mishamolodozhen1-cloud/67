"""Управление подключёнными товарами: склад, выдача, настройки лота."""

from __future__ import annotations

import io
import json

from aiogram import F, Router
from aiogram.fsm.context import FSMContext
from aiogram.types import BufferedInputFile, CallbackQuery, Message

from db import db
from engine import DEFAULT_DELIVERY
from keyboards import BLUE, GREEN, back, btn, cancel, kb, toggle
from plugins import PLUGINS, get_plugin
from plugins.gmail import GmailPlugin
from states import ProductEdit

from .common import esc, get_engine, plural, show

router = Router()

MAX_FILE = 5 * 1024 * 1024


async def _product(call_or_msg, product_id: int) -> dict | None:
    product = await db.get_product(product_id, call_or_msg.from_user.id)
    if product is None:
        await show(call_or_msg, "Товар не найден.", kb([back("products")]))
    return product


# --- список -----------------------------------------------------------------


@router.callback_query(F.data == "products")
async def cb_products(call: CallbackQuery, state: FSMContext) -> None:
    await state.clear()
    if not await get_engine(call):
        return
    products = await db.products(call.from_user.id)
    if not products:
        await show(
            call,
            "📦 <b>Мои товары</b>\n\nПока ни один лот не подключён.\n"
            "Нажмите «📥 Загрузить с Playerok» и выберите лот.",
            kb([[btn("📥 Загрузить с Playerok", "pk_items:0", GREEN)], back()]),
        )
        return
    rows = []
    for p in products:
        plugin = get_plugin(p["plugin"])
        per = max(1, p["per_payment"] or 1)
        state_icon = "🟢" if p["enabled"] else "⏸"
        rows.append(
            [
                btn(
                    f"{state_icon}{plugin.emoji} {p['name'][:30]} · {p['stock_count']} шт.",
                    f"prod:{p['id']}",
                    GREEN if p["stock_count"] >= per else BLUE,
                )
            ]
        )
    rows.append([btn("📥 Добавить лот", "pk_items:0", GREEN), btn("⬅️ Меню", "menu")])
    total = sum(p["stock_count"] for p in products)
    await show(
        call,
        f"📦 <b>Мои товары</b> ({len(products)})\n"
        f"Всего на складе: <b>{total}</b>\n\n🟢 — автовыдача включена, ⏸ — выключена",
        kb(rows),
    )


# --- карточка ---------------------------------------------------------------


async def product_card(target, product_id: int) -> None:
    product = await _product(target, product_id)
    if not product:
        return
    plugin = get_plugin(product["plugin"])
    stock = await db.stock_count(product_id)
    sold = len(await db.stock_list(product_id, "sold"))
    per = max(1, product["per_payment"] or 1)
    sales = stock // per
    per_text = "поштучно (1 за оплату)" if per == 1 else f"{per} шт. за одну оплату"
    text = (
        f"{plugin.emoji} <b>{esc(product['name'])}</b>\n"
        f"Плагин: <b>{plugin.title}</b>\n\n"
        f"💵 Цена лота: <b>{product['price']:g} ₽</b>\n"
        f"📦 На складе: <b>{stock}</b> {plural(stock, 'единица', 'единицы', 'единиц')}"
        f" → хватит на <b>{sales}</b> {plural(sales, 'продажу', 'продажи', 'продаж')}\n"
        f"🔢 Выдача: <b>{per_text}</b>\n"
        f"✅ Продано: <b>{sold}</b>\n\n"
        f"⚡️ Автовыдача: {'🟢 вкл' if product['enabled'] else '⚪️ выкл'}\n"
        f"♻️ Авто-восстановление лота после продажи: {'🟢' if product['auto_relist'] else '⚪️'}\n"
        f"⏸ Снимать лот, когда склад пуст: {'🟢' if product['auto_disable'] else '⚪️'}"
    )
    pid = product_id
    rows = [
        [btn("➕ Загрузить наличие", f"stk_add:{pid}", GREEN), btn("📋 Склад", f"stk_view:{pid}", BLUE)],
        [btn(f"🔢 За оплату: {per} шт.", f"per:{pid}", BLUE), btn("✏️ Текст выдачи", f"dtext:{pid}", BLUE)],
        [toggle("Автовыдача", bool(product["enabled"]), f"pt:enabled:{pid}")],
        [
            toggle("Авто-восст.", bool(product["auto_relist"]), f"pt:auto_relist:{pid}"),
            toggle("Снимать при 0", bool(product["auto_disable"]), f"pt:auto_disable:{pid}"),
        ],
        [btn("💲 Цена", f"price:{pid}", BLUE), btn("⏸ Снять лот", f"lot_off:{pid}", BLUE), btn("▶️ Выставить", f"lot_on:{pid}", GREEN)],
        [btn("📤 Выгрузить .txt", f"stk_export:{pid}", BLUE), btn("🧹 Очистить склад", f"stk_clear:{pid}", BLUE)],
        [btn("🧪 Тест выдачи", f"preview:{pid}", GREEN), btn("🔁 Плагин", f"plug:{pid}", BLUE)],
        [btn("❌ Отключить товар", f"pdel:{pid}", BLUE)],
        [btn("⬅️ Мои товары", "products"), btn("🏠 Меню", "menu", GREEN)],
    ]
    if product["item_slug"]:
        rows.insert(-2, [btn("🔗 Лот на Playerok", url=f"https://playerok.com/products/{product['item_slug']}")])
    await show(target, text, kb(rows))


@router.callback_query(F.data.startswith("prod:"))
async def cb_product(call: CallbackQuery, state: FSMContext) -> None:
    await state.clear()
    await product_card(call, int(call.data.split(":")[1]))


@router.callback_query(F.data.startswith("pt:"))
async def cb_toggle(call: CallbackQuery) -> None:
    _, field, pid = call.data.split(":")
    if await _product(call, int(pid)):
        await db.toggle_product(int(pid), field)
        await product_card(call, int(pid))


# --- склад ------------------------------------------------------------------


@router.callback_query(F.data.startswith("stk_add:"))
async def cb_stock_add(call: CallbackQuery, state: FSMContext) -> None:
    pid = int(call.data.split(":")[1])
    product = await _product(call, pid)
    if not product:
        return
    plugin = get_plugin(product["plugin"])
    await state.set_state(ProductEdit.stock)
    await state.update_data(product_id=pid)
    await show(
        call,
        f"➕ <b>Загрузка наличия</b> — {esc(product['name'])}\n\n{plugin.input_help}\n\n"
        "Можно отправить несколько сообщений подряд. Когда закончите — нажмите «Готово».",
        kb([[btn("✅ Готово", f"prod:{pid}", GREEN)]]),
    )


async def _import_stock(message: Message, state: FSMContext, text: str) -> None:
    data = await state.get_data()
    pid = data.get("product_id")
    product = await db.get_product(pid, message.from_user.id) if pid else None
    if not product:
        await state.clear()
        await message.answer("Товар не найден.")
        return
    plugin = get_plugin(product["plugin"])
    result = plugin.parse(text)

    existing = await db.existing_stock_data(pid)
    if isinstance(plugin, GmailPlugin):
        known = {GmailPlugin.key_of(e) for e in existing}
        fresh = [e for e in result.entries if GmailPlugin.key_of(e) not in known]
    else:
        fresh = [e for e in result.entries if e not in existing]
    dup_db = len(result.entries) - len(fresh)
    added = await db.add_stock(pid, fresh) if fresh else 0
    total = await db.stock_count(pid)

    report = [f"📥 <b>Загружено: {added}</b>", f"📦 Теперь на складе: <b>{total}</b>"]
    if result.duplicates or dup_db:
        report.append(f"♊️ Пропущено дублей: {result.duplicates + dup_db}")
    if result.errors:
        report.append(f"⚠️ Ошибок: {len(result.errors)}")
        report.extend(f"  • {esc(e)}" for e in result.errors[:10])
        if len(result.errors) > 10:
            report.append(f"  … и ещё {len(result.errors) - 10}")

    retried = 0
    if added:
        from engine import manager

        engine = manager.get(message.from_user.id)
        if engine:
            retried = await engine.retry_waiting(pid)
    if retried:
        report.append(f"\n🚚 Выданы ожидавшие заказы: {retried}")

    await message.answer(
        "\n".join(report) + "\n\nМожно прислать ещё или нажать «Готово».",
        reply_markup=kb([[btn("✅ Готово", f"prod:{pid}", GREEN), btn("📋 Склад", f"stk_view:{pid}")]]),
    )


@router.message(ProductEdit.stock, F.document)
async def got_stock_file(message: Message, state: FSMContext) -> None:
    doc = message.document
    if doc.file_size and doc.file_size > MAX_FILE:
        await message.answer("Файл слишком большой (макс. 5 МБ).")
        return
    buf = io.BytesIO()
    await message.bot.download(doc, destination=buf)
    raw = buf.getvalue()
    for enc in ("utf-8-sig", "cp1251", "latin-1"):
        try:
            text = raw.decode(enc)
            break
        except UnicodeDecodeError:
            continue
    await _import_stock(message, state, text)


@router.message(ProductEdit.stock, F.text)
async def got_stock_text(message: Message, state: FSMContext) -> None:
    try:
        await message.delete()  # не храним данные аккаунтов в истории чата
    except Exception:
        pass
    await _import_stock(message, state, message.text)


@router.callback_query(F.data.startswith("stk_view:"))
async def cb_stock_view(call: CallbackQuery) -> None:
    pid = int(call.data.split(":")[1])
    product = await _product(call, pid)
    if not product:
        return
    plugin = get_plugin(product["plugin"])
    available = await db.stock_list(pid)
    sold = await db.stock_list(pid, "sold")
    lines = [f"📋 <b>Склад</b> — {esc(product['name'])}", f"В наличии: <b>{len(available)}</b> · Продано: <b>{len(sold)}</b>\n"]
    for i, row in enumerate(available[:40], 1):
        lines.append(f"{i}. <code>{esc(plugin.preview(row['data']))}</code>")
    if len(available) > 40:
        lines.append(f"… и ещё {len(available) - 40}. Полный список — «Выгрузить .txt».")
    if not available:
        lines.append("Склад пуст.")
    await show(
        call,
        "\n".join(lines),
        kb(
            [
                [btn("➕ Загрузить", f"stk_add:{pid}", GREEN), btn("📤 Выгрузить .txt", f"stk_export:{pid}")],
                back(f"prod:{pid}"),
            ]
        ),
    )


def _raw_line(plugin_key: str, entry: str) -> str:
    if plugin_key == "gmail":
        acc = GmailPlugin.load(entry)
        parts = [acc.get("email", ""), acc.get("password", "")]
        if acc.get("recovery") or acc.get("extra"):
            parts.append(acc.get("recovery", ""))
        if acc.get("extra"):
            parts.append(acc["extra"])
        return "|".join(parts)
    return entry


@router.callback_query(F.data.startswith("stk_export:"))
async def cb_stock_export(call: CallbackQuery) -> None:
    pid = int(call.data.split(":")[1])
    product = await _product(call, pid)
    if not product:
        return
    available = await db.stock_list(pid)
    sold = await db.stock_list(pid, "sold")
    out = ["# В наличии"] + [_raw_line(product["plugin"], r["data"]) for r in available]
    out += ["", "# Продано (id сделки)"] + [
        f"{_raw_line(product['plugin'], r['data'])}  # {r['deal_id']}" for r in sold
    ]
    file = BufferedInputFile("\n".join(out).encode("utf-8"), filename=f"stock_{pid}.txt")
    await call.message.answer_document(file, caption=f"📤 Склад «{esc(product['name'])}»")
    await call.answer()


@router.callback_query(F.data.startswith("stk_clear:"))
async def cb_stock_clear(call: CallbackQuery) -> None:
    pid = int(call.data.split(":")[1])
    if not await _product(call, pid):
        return
    count = await db.stock_count(pid)
    await show(
        call,
        f"🧹 Удалить со склада все <b>{count}</b> непроданных единиц? Это нельзя отменить.",
        kb([[btn("✅ Да, очистить", f"stk_clear_ok:{pid}", GREEN), btn("✖️ Отмена", f"prod:{pid}")]]),
    )


@router.callback_query(F.data.startswith("stk_clear_ok:"))
async def cb_stock_clear_ok(call: CallbackQuery) -> None:
    pid = int(call.data.split(":")[1])
    if await _product(call, pid):
        await db.clear_stock(pid)
        await call.answer("Склад очищен")
        await product_card(call, pid)


# --- количество за оплату -----------------------------------------------------


@router.callback_query(F.data.startswith("per:"))
async def cb_per(call: CallbackQuery, state: FSMContext) -> None:
    pid = int(call.data.split(":")[1])
    if not await _product(call, pid):
        return
    await state.set_state(ProductEdit.per_payment)
    await state.update_data(product_id=pid)
    quick = [1, 2, 3, 5, 10, 20, 50, 100]
    rows = [
        [btn(f"{n} шт." if n > 1 else "Поштучно", f"perset:{pid}:{n}", GREEN if n == 1 else BLUE) for n in quick[:4]],
        [btn(f"{n} шт.", f"perset:{pid}:{n}") for n in quick[4:]],
        back(f"prod:{pid}"),
    ]
    await show(
        call,
        "🔢 <b>Сколько единиц выдавать за одну оплату?</b>\n\n"
        "• <b>Поштучно</b> — 1 аккаунт за оплату.\n"
        "• Пачка — например, лот «5 Gmail аккаунтов» → 5 за оплату.\n\n"
        "Выберите вариант или отправьте число (1–1000).",
        kb(rows),
    )


async def _set_per(target, state: FSMContext, pid: int, value: int) -> None:
    await db.set_product_field(pid, "per_payment", value)
    await state.clear()
    await product_card(target, pid)


@router.callback_query(F.data.startswith("perset:"))
async def cb_perset(call: CallbackQuery, state: FSMContext) -> None:
    _, pid, n = call.data.split(":")
    if await _product(call, int(pid)):
        await _set_per(call, state, int(pid), int(n))


@router.message(ProductEdit.per_payment, F.text)
async def got_per(message: Message, state: FSMContext) -> None:
    pid = (await state.get_data()).get("product_id")
    if not message.text.strip().isdigit() or not 1 <= int(message.text.strip()) <= 1000:
        await message.answer("Введите число от 1 до 1000.")
        return
    if await _product(message, pid):
        await _set_per(message, state, pid, int(message.text.strip()))


# --- текст выдачи -------------------------------------------------------------


@router.callback_query(F.data.startswith("dtext:"))
async def cb_dtext(call: CallbackQuery, state: FSMContext) -> None:
    pid = int(call.data.split(":")[1])
    product = await _product(call, pid)
    if not product:
        return
    await state.set_state(ProductEdit.delivery_text)
    await state.update_data(product_id=pid)
    current = product["delivery_text"] or DEFAULT_DELIVERY
    await show(
        call,
        "✏️ <b>Текст выдачи товара</b>\n\nТекущий:\n"
        f"<pre>{esc(current)}</pre>\n"
        "Переменные:\n<code>{buyer}</code> — ник покупателя\n<code>{item}</code> — название лота\n"
        "<code>{qty}</code> — количество\n<code>{goods}</code> — сам товар (аккаунты)\n\n"
        "Отправьте новый текст:",
        kb([[btn("↩️ Сбросить по умолчанию", f"dreset:{pid}", GREEN)], back(f"prod:{pid}")]),
    )


@router.callback_query(F.data.startswith("dreset:"))
async def cb_dreset(call: CallbackQuery, state: FSMContext) -> None:
    pid = int(call.data.split(":")[1])
    if await _product(call, pid):
        await db.set_product_field(pid, "delivery_text", None)
        await state.clear()
        await call.answer("Текст сброшен")
        await product_card(call, pid)


@router.message(ProductEdit.delivery_text, F.text)
async def got_dtext(message: Message, state: FSMContext) -> None:
    pid = (await state.get_data()).get("product_id")
    if not await _product(message, pid):
        return
    text = message.text
    if "{goods}" not in text:
        text += "\n\n{goods}"
        await message.answer("ℹ️ В тексте не было {goods} — товар будет добавлен в конец.")
    await db.set_product_field(pid, "delivery_text", text)
    await state.clear()
    await message.answer("✅ Текст выдачи сохранён.")
    await product_card(message, pid)


@router.callback_query(F.data.startswith("preview:"))
async def cb_preview(call: CallbackQuery) -> None:
    pid = int(call.data.split(":")[1])
    product = await _product(call, pid)
    if not product:
        return
    plugin = get_plugin(product["plugin"])
    per = max(1, product["per_payment"] or 1)
    if plugin.key == "gmail":
        sample = [json.dumps({"email": f"example{i}@gmail.com", "password": "Passw0rd!", "recovery": "backup@mail.ru", "extra": ""}) for i in range(1, per + 1)]
    else:
        sample = [f"XXXX-XXXX-XXXX-{i:04d}" for i in range(1, per + 1)]
    goods = plugin.format_goods(sample)
    template = product["delivery_text"] or DEFAULT_DELIVERY
    from engine import render

    text = render(template, buyer="Покупатель", item=product["name"], qty=per, goods=goods, deal="—")
    await show(
        call,
        "🧪 <b>Так покупатель увидит выдачу</b> (с примерными данными):\n\n" f"<pre>{esc(text)}</pre>",
        kb([back(f"prod:{pid}")]),
    )


# --- цена и лот на Playerok ---------------------------------------------------


@router.callback_query(F.data.startswith("price:"))
async def cb_price(call: CallbackQuery, state: FSMContext) -> None:
    pid = int(call.data.split(":")[1])
    product = await _product(call, pid)
    if not product:
        return
    await state.set_state(ProductEdit.price)
    await state.update_data(product_id=pid)
    await show(
        call,
        f"💲 Текущая цена: <b>{product['price']:g} ₽</b>\nОтправьте новую цену лота (в рублях):",
        cancel(f"prod:{pid}"),
    )


@router.message(ProductEdit.price, F.text)
async def got_price(message: Message, state: FSMContext) -> None:
    pid = (await state.get_data()).get("product_id")
    product = await _product(message, pid)
    if not product:
        return
    try:
        price = float(message.text.replace(",", ".").replace("₽", "").strip())
        assert price > 0
    except (ValueError, AssertionError):
        await message.answer("Введите положительное число, например 149.")
        return
    engine = await get_engine(message)
    if not engine:
        return
    try:
        await engine.account.items.update(product["item_id"], {"price": price})
    except Exception as exc:
        await message.answer(f"⚠️ Playerok не принял цену: <code>{esc(str(exc))[:300]}</code>")
        return
    await db.set_product_field(pid, "price", price)
    await state.clear()
    await message.answer(f"✅ Цена изменена на {price:g} ₽")
    await product_card(message, pid)


@router.callback_query(F.data.startswith("lot_off:") | F.data.startswith("lot_on:"))
async def cb_lot(call: CallbackQuery) -> None:
    action, pid = call.data.split(":")
    product = await _product(call, int(pid))
    engine = await get_engine(call)
    if not product or not engine:
        return
    try:
        if action == "lot_off":
            await engine.account.items.discontinue(product["item_id"])
            await call.answer("⏸ Лот снят с продажи", show_alert=True)
        else:
            await engine.account.items.republish(product["item_id"])
            await call.answer("▶️ Лот выставлен на продажу", show_alert=True)
    except Exception as exc:
        await call.answer(f"Ошибка Playerok: {str(exc)[:180]}", show_alert=True)


# --- плагин и удаление --------------------------------------------------------


@router.callback_query(F.data.startswith("plug:"))
async def cb_plugin(call: CallbackQuery) -> None:
    pid = int(call.data.split(":")[1])
    product = await _product(call, pid)
    if not product:
        return
    rows = [
        [btn(f"{p.emoji} {p.title}", f"plugset:{pid}:{p.key}", GREEN if p.key == product["plugin"] else BLUE)]
        for p in PLUGINS.values()
    ]
    rows.append(back(f"prod:{pid}"))
    await show(
        call,
        "🔁 <b>Плагин товара</b>\nОпределяет формат загрузки наличия и вид выдачи.\n"
        "⚠️ При смене плагина текущий склад лучше очистить.",
        kb(rows),
    )


@router.callback_query(F.data.startswith("plugset:"))
async def cb_plugin_set(call: CallbackQuery) -> None:
    _, pid, key = call.data.split(":")
    if key in PLUGINS and await _product(call, int(pid)):
        await db.set_product_field(int(pid), "plugin", key)
        await product_card(call, int(pid))


@router.callback_query(F.data.startswith("pdel:"))
async def cb_pdel(call: CallbackQuery) -> None:
    pid = int(call.data.split(":")[1])
    product = await _product(call, pid)
    if not product:
        return
    stock = await db.stock_count(pid)
    await show(
        call,
        f"❌ Отключить «{esc(product['name'])}» от бота?\n"
        f"Склад ({stock} шт.) будет удалён. Сам лот на Playerok останется.\n"
        "Совет: сначала выгрузите склад в .txt.",
        kb(
            [
                [btn("📤 Выгрузить склад", f"stk_export:{pid}", GREEN)],
                [btn("✅ Да, отключить", f"pdel_ok:{pid}", GREEN), btn("✖️ Отмена", f"prod:{pid}")],
            ]
        ),
    )


@router.callback_query(F.data.startswith("pdel_ok:"))
async def cb_pdel_ok(call: CallbackQuery) -> None:
    pid = int(call.data.split(":")[1])
    if await _product(call, pid):
        await db.delete_product(pid)
        await call.answer("Товар отключён")
        await show(call, "✅ Товар отключён от бота.", kb([[btn("📦 Мои товары", "products", GREEN)], back()]))
