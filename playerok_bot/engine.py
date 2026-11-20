"""Движок автоматизации: следит за сделками и чатами Playerok одного пользователя.

* Автовыдача: оплаченная сделка → берём товар со склада → отправляем в чат
  сделки → отмечаем сделку «Отправлено» → уведомляем продавца.
* Автоответчик: приветствие, команда !наличие, правила по ключевым словам.
* Уведомления продавцу в Telegram с кнопкой «Ответить».

События берутся из WebSocket-подписок Playerok, а поллинг сделок и чатов
работает параллельно как страховка (дубли отсекаются по id).
"""

from __future__ import annotations

import asyncio
import html
import logging
import time
from collections import OrderedDict
from typing import Any

from aiogram import Bot
from PlayerokAPI import (
    Account,
    Deal,
    EventType,
    GraphQLError,
    ItemDealDirection,
    ItemDealStatus,
    UnauthorizedError,
)

import config
from db import db
from keyboards import btn, kb
from plugins import get_plugin

log = logging.getLogger("engine")

DEFAULT_DELIVERY = (
    "✅ Спасибо за покупку, {buyer}!\n\n"
    "Ваш заказ «{item}» ({qty} шт.):\n\n"
    "{goods}\n\n"
    "Пожалуйста, подтвердите выполнение заказа и оставьте отзыв 🙏"
)
NO_STOCK_MSG = (
    "Здравствуйте, {buyer}! Оплата получена ✅ Товар временно закончился на складе — "
    "продавец выдаст его вручную в ближайшее время. Спасибо за ожидание!"
)
STOCK_COMMANDS = {"!наличие", "!товары", "!stock", "!склад"}


class _Seen:
    """Ограниченное множество уже обработанных id."""

    def __init__(self, size: int = 3000) -> None:
        self._data: OrderedDict[str, None] = OrderedDict()
        self._size = size

    def add(self, key: str) -> bool:
        """True — если ключ новый."""
        if key in self._data:
            return False
        self._data[key] = None
        if len(self._data) > self._size:
            self._data.popitem(last=False)
        return True


def chunks(text: str, limit: int = config.PLAYEROK_MSG_LIMIT) -> list[str]:
    """Режем длинный текст по абзацам/строкам, чтобы влезть в лимит чата."""
    if len(text) <= limit:
        return [text]
    parts: list[str] = []
    current = ""
    for block in text.split("\n"):
        candidate = f"{current}\n{block}" if current else block
        if len(candidate) > limit and current:
            parts.append(current)
            current = block
        else:
            current = candidate
        while len(current) > limit:
            parts.append(current[:limit])
            current = current[limit:]
    if current:
        parts.append(current)
    return parts


def _status(value: Any) -> str:
    return str(getattr(value, "value", value))


def render(template: str, **values: Any) -> str:
    out = template
    for key, value in values.items():
        out = out.replace("{" + key + "}", str(value))
    return out


class Engine:
    def __init__(self, tg_id: int, token: str, bot: Bot) -> None:
        self.tg_id = tg_id
        self.bot = bot
        self.account = Account(token, rate_limit=(5, 1.0), proxy=config.PLAYEROK_PROXY)
        self.me_id: str | None = None
        self.username: str | None = None
        self.status = "запускается…"
        self.started_at = time.time()
        self._tasks: list[asyncio.Task] = []
        self._deal_lock = asyncio.Lock()
        self._seen_messages = _Seen()
        self._seen_deal_events = _Seen()
        self._deal_filter_ok = True
        self._auth_failed = False

    # --- жизненный цикл ------------------------------------------------------

    async def start(self) -> None:
        me = await self.account.get_me()
        self.me_id, self.username = me.id, me.username
        self._tasks = [
            asyncio.create_task(self._deals_loop(), name=f"deals-{self.tg_id}"),
            asyncio.create_task(self._chats_loop(), name=f"chats-{self.tg_id}"),
            asyncio.create_task(self._ws_loop(), name=f"ws-{self.tg_id}"),
        ]
        self.status = "🟢 работает"
        log.info("Движок %s (%s) запущен", self.tg_id, self.username)

    async def stop(self) -> None:
        for task in self._tasks:
            task.cancel()
        for task in self._tasks:
            try:
                await task
            except (asyncio.CancelledError, Exception):
                pass
        self._tasks = []
        try:
            await self.account.aclose()
        except Exception:
            pass
        self.status = "🔴 остановлен"

    # --- утилиты -------------------------------------------------------------

    async def notify(self, text: str, markup=None) -> None:
        try:
            await self.bot.send_message(
                self.tg_id, text, reply_markup=markup, disable_web_page_preview=True
            )
        except Exception as exc:
            log.warning("Не удалось отправить уведомление %s: %s", self.tg_id, exc)

    async def send_chat(self, chat_id: str, text: str) -> None:
        for part in chunks(text):
            await self.account.send_message(chat_id, part)
            await asyncio.sleep(0.4)

    async def _on_auth_error(self) -> None:
        if self._auth_failed:
            return
        self._auth_failed = True
        self.status = "🔴 токен недействителен"
        await self.notify(
            "⚠️ <b>Токен Playerok перестал работать.</b>\n"
            "Скорее всего, вы вышли из аккаунта на сайте. Подключите новый токен.",
            kb([[btn("🔑 Подключить заново", "connect", "success")]]),
        )

    # --- сделки --------------------------------------------------------------

    async def _fetch_paid_deals(self) -> list[Deal]:
        if self._deal_filter_ok:
            try:
                page = await self.account.deals.search(
                    filter={"direction": "OUT", "status": ["PAID"]}, first=25
                )
                return list(page)
            except GraphQLError as exc:
                log.warning("Фильтр сделок не принят (%s), перехожу на общий список", exc)
                self._deal_filter_ok = False
        page = await self.account.deals.search(filter={"userId": self.me_id}, first=40)
        return [
            d
            for d in page
            if d.status == ItemDealStatus.PAID and d.direction in (ItemDealDirection.OUT, None)
        ]

    async def _deals_loop(self) -> None:
        while True:
            try:
                for deal in await self._fetch_paid_deals():
                    await self.handle_paid(deal)
                if self._auth_failed:
                    self._auth_failed = False
                    self.status = "🟢 работает"
            except asyncio.CancelledError:
                raise
            except UnauthorizedError:
                await self._on_auth_error()
            except Exception as exc:
                log.warning("Поллинг сделок %s: %s", self.tg_id, exc)
            await asyncio.sleep(config.DEALS_POLL_INTERVAL)

    async def handle_paid(self, deal: Deal, *, force: bool = False) -> str:
        """Обработать оплаченную сделку. Возвращает итоговый статус."""
        async with self._deal_lock:
            return await self._handle_paid(deal, force=force)

    async def _handle_paid(self, deal: Deal, *, force: bool) -> str:
        known = await db.deal_known(deal.id)
        # «no_stock» перепроверяем на каждом проходе: вдруг склад пополнили.
        if known and not force and known["status"] != "no_stock":
            return known["status"]
        if known and known["status"] == "delivered":
            return "delivered"

        user = await db.get_user(self.tg_id)
        if not user:
            return "no_user"
        buyer = deal.user.username if deal.user and deal.user.username else "покупатель"
        item_id = deal.item.id if deal.item else None
        item_name = deal.item.name if deal.item and deal.item.name else "товар"
        amount = deal.item.price if deal.item else 0
        created = deal.created_at.timestamp() if deal.created_at else time.time()

        base = dict(
            deal_id=deal.id,
            tg_id=self.tg_id,
            item_name=item_name,
            buyer=buyer,
            amount=amount or 0,
            created_at=created,
        )

        # Сделки, оплаченные до подключения бота, не трогаем автоматически.
        if not force and created < (user["connected_at"] or 0) - 60:
            await db.save_deal(**base, status="old", qty=0)
            return "old"

        product = None
        if item_id:
            product = await db.product_by_item(self.tg_id, item_id)
        if product is None and item_name:
            product = await db.product_by_name(self.tg_id, item_name)

        deal_link = f"https://playerok.com/deal/{deal.id}"
        head = (
            f"💸 <b>Новая оплата!</b>\n"
            f"Товар: <b>{html.escape(item_name)}</b>\n"
            f"Покупатель: <b>{html.escape(buyer)}</b>\n"
            f"Сумма: <b>{amount:g} ₽</b>\n"
        )

        if product is None or not product["enabled"] or not user["auto_delivery"]:
            await db.save_deal(
                **base, product_id=product["id"] if product else None, status="manual", qty=0
            )
            if user["notify_deals"]:
                reason = (
                    "товар не подключён к боту"
                    if product is None
                    else "автовыдача выключена"
                )
                await self.notify(
                    head + f"\n✋ Нужна ручная выдача ({reason}).",
                    kb([[btn("🔗 Открыть сделку", url=deal_link, style="primary")]]),
                )
            return "manual"

        plugin = get_plugin(product["plugin"])
        qty = max(1, int(product["per_payment"] or 1))
        chat_id = deal.chat_id
        if not chat_id:
            try:
                chat_id = (await self.account.deals.get(deal.id)).chat_id
            except Exception as exc:
                log.warning("Не удалось получить чат сделки %s: %s", deal.id, exc)

        goods = await db.take_stock(product["id"], qty, deal.id)
        if goods is None:
            left = await db.stock_count(product["id"])
            await db.save_deal(**base, product_id=product["id"], chat_id=chat_id, status="no_stock", qty=qty)
            if known and known["status"] == "no_stock":
                return "no_stock"  # уже предупреждали
            if chat_id:
                try:
                    await self.send_chat(chat_id, render(NO_STOCK_MSG, buyer=buyer))
                except Exception as exc:
                    log.warning("Сообщение о нехватке не отправлено: %s", exc)
            await self.notify(
                head
                + f"\n❗️ <b>Не хватает товара на складе!</b> Нужно {qty}, есть {left}.\n"
                "Пополните склад — бот выдаст заказ автоматически.",
                kb(
                    [
                        [btn("➕ Пополнить склад", f"stk_add:{product['id']}", "success")],
                        [btn("🔗 Открыть сделку", url=deal_link, style="primary")],
                    ]
                ),
            )
            return "no_stock"

        if not chat_id:
            await db.return_stock(deal.id)
            await db.save_deal(**base, product_id=product["id"], status="error", qty=qty)
            await self.notify(head + "\n⚠️ Не найден чат сделки, выдайте товар вручную.")
            return "error"

        template = product["delivery_text"] or DEFAULT_DELIVERY
        if "{goods}" not in template:
            template += "\n\n{goods}"
        text = render(
            template,
            buyer=buyer,
            item=item_name,
            qty=qty,
            goods=plugin.format_goods(goods),
            deal=deal.id,
        )
        try:
            await self.send_chat(chat_id, text)
        except Exception as exc:
            await db.return_stock(deal.id)
            await db.save_deal(**base, product_id=product["id"], chat_id=chat_id, status="error", qty=qty)
            await self.notify(
                head + f"\n⚠️ Ошибка отправки товара: <code>{html.escape(str(exc))[:300]}</code>\n"
                "Товар возвращён на склад. Нажмите, чтобы повторить выдачу.",
                kb([[btn("🔁 Повторить выдачу", f"redeliver:{deal.id}", "success")]]),
            )
            return "error"

        completed = ""
        if user["auto_complete"]:
            try:
                await self.account.deals.update(deal.id, {"status": ItemDealStatus.SENT.value})
                completed = "\n📨 Сделка отмечена как «Отправлено»."
            except Exception as exc:
                completed = f"\n⚠️ Не удалось отметить сделку отправленной: {html.escape(str(exc))[:150]}"

        await db.save_deal(**base, product_id=product["id"], chat_id=chat_id, status="delivered", qty=qty)
        left = await db.stock_count(product["id"])
        sales_left = left // qty

        extra = await self._after_sale(product, left, qty)

        if user["notify_deals"]:
            low = ""
            if left < qty:
                low = "\n🚨 <b>Склад пуст!</b>"
            elif sales_left <= (user["low_stock"] or 0):
                low = f"\n⚠️ Заканчивается товар: хватит на {sales_left} продаж."
            await self.notify(
                head
                + f"\n✅ <b>Выдано автоматически:</b> {qty} {plugin.unit}"
                + f"\n📦 Осталось: {left} (≈ {sales_left} продаж)"
                + completed
                + low
                + extra,
                kb(
                    [
                        [
                            btn("📦 Товар", f"prod:{product['id']}", "primary"),
                            btn("🔗 Сделка", url=deal_link, style="success"),
                        ]
                    ]
                ),
            )
        return "delivered"

    async def _after_sale(self, product: dict, left: int, qty: int) -> str:
        item_id = product["item_id"]
        if left < qty and product["auto_disable"]:
            try:
                await self.account.items.discontinue(item_id)
                return "\n⏸ Лот снят с продажи — склад пуст."
            except Exception as exc:
                return f"\n⚠️ Не удалось снять лот: {html.escape(str(exc))[:150]}"
        if left >= qty and product["auto_relist"]:
            await asyncio.sleep(2)
            try:
                await self.account.items.republish(item_id)
                return "\n♻️ Лот снова выставлен на продажу."
            except Exception as exc:
                return f"\n⚠️ Авто-восстановление лота не удалось: {html.escape(str(exc))[:150]}"
        return ""

    async def retry_waiting(self, product_id: int) -> int:
        """После пополнения склада выдать заказы, которые ждали товара."""
        waiting = await db._all(
            "SELECT deal_id FROM deals WHERE tg_id=? AND product_id=? AND status IN ('no_stock','error') "
            "ORDER BY created_at",
            (self.tg_id, product_id),
        )
        done = 0
        for row in waiting:
            try:
                deal = await self.account.deals.get(row["deal_id"])
            except Exception as exc:
                log.warning("Сделка %s не получена: %s", row["deal_id"], exc)
                continue
            if deal.status != ItemDealStatus.PAID:
                await db.save_deal(deal_id=deal.id, tg_id=self.tg_id, status="closed_" + _status(deal.status))
                continue
            if await self.handle_paid(deal, force=True) == "delivered":
                done += 1
        return done

    async def redeliver(self, deal_id: str) -> str:
        deal = await self.account.deals.get(deal_id)
        if deal.status != ItemDealStatus.PAID:
            return "сделка в статусе " + _status(deal.status)
        return await self.handle_paid(deal, force=True)

    async def _on_deal_event(self, event) -> None:
        deal: Deal | None = event.deal
        if deal is None or deal.status is None:
            return
        if not self._seen_deal_events.add(f"{deal.id}:{deal.status}"):
            return
        if deal.status == ItemDealStatus.PAID and deal.direction != ItemDealDirection.IN:
            await self.handle_paid(deal)
        elif deal.status == ItemDealStatus.CONFIRMED and deal.direction != ItemDealDirection.IN:
            user = await db.get_user(self.tg_id)
            if user and user["notify_deals"]:
                name = deal.item.name if deal.item else "товар"
                await self.notify(f"🎉 Покупатель подтвердил сделку «{html.escape(name or '')}».")
        elif deal.status == ItemDealStatus.ROLLED_BACK and deal.direction != ItemDealDirection.IN:
            await db.save_deal(deal_id=deal.id, tg_id=self.tg_id, status="refund")
            await self.notify(
                f"↩️ Возврат по сделке «{html.escape(deal.item.name if deal.item and deal.item.name else '')}».",
                kb([[btn("🔗 Сделка", url=f"https://playerok.com/deal/{deal.id}", style="primary")]]),
            )

    # --- чаты и автоответчик -------------------------------------------------

    async def _chats_loop(self) -> None:
        while True:
            try:
                runner = self.account.polling(interval=config.CHATS_POLL_INTERVAL)
                async for event in runner.events():
                    if event.type == EventType.NEW_MESSAGE:
                        await self.handle_message(event.message)
            except asyncio.CancelledError:
                raise
            except UnauthorizedError:
                await self._on_auth_error()
            except Exception as exc:
                log.warning("Поллинг чатов %s: %s", self.tg_id, exc)
            await asyncio.sleep(15)

    async def _ws_loop(self) -> None:
        while True:
            try:
                listener = self.account.listener(
                    events=[EventType.NEW_MESSAGE, EventType.NEW_DEAL, EventType.DEAL_UPDATED]
                )
                async for event in listener.events():
                    try:
                        if event.type == EventType.NEW_MESSAGE:
                            await self.handle_message(event.message)
                        else:
                            await self._on_deal_event(event)
                    except Exception:
                        log.exception("Ошибка обработки события")
            except asyncio.CancelledError:
                raise
            except Exception as exc:
                log.info("WebSocket %s недоступен (%s), работаю на поллинге", self.tg_id, exc)
            await asyncio.sleep(60)

    async def handle_message(self, message) -> None:
        if message is None or not message.id or not self._seen_messages.add(message.id):
            return
        if message.is_system or message.author_id == self.me_id:
            return
        text = (message.text or "").strip()
        chat_id = message.chat_id
        if not chat_id or not text or text.startswith("{{"):
            return
        user = await db.get_user(self.tg_id)
        if not user:
            return
        buyer = message.user.username if message.user and message.user.username else "покупатель"

        if user["notify_messages"]:
            await self.notify(
                f"💬 <b>{html.escape(buyer)}</b>:\n{html.escape(text[:1500])}",
                kb(
                    [
                        [
                            btn("✍️ Ответить", f"rp:{chat_id}", "success"),
                            btn("🔗 Чат", url=f"https://playerok.com/chats/{chat_id}", style="primary"),
                        ]
                    ]
                ),
            )

        if not user["autoreply"]:
            return
        try:
            await self._autoreply(user, chat_id, buyer, text)
        except Exception as exc:
            log.warning("Автоответ не отправлен: %s", exc)

    async def _autoreply(self, user: dict, chat_id: str, buyer: str, text: str) -> None:
        lowered = text.lower()

        if user["greeting_on"] and not await db.was_greeted(self.tg_id, chat_id):
            await db.mark_greeted(self.tg_id, chat_id)
            await self.send_chat(chat_id, render(user["greeting_text"] or "", buyer=buyer))

        if user["stock_command"] and lowered in STOCK_COMMANDS:
            await self.send_chat(chat_id, await self.stock_text())
            return

        for rule in await db.autoreplies(self.tg_id):
            triggers = [t.strip().lower() for t in rule["triggers"].split(",") if t.strip()]
            hit = any((lowered == t) if rule["exact"] else (t in lowered) for t in triggers)
            if hit:
                await self.send_chat(chat_id, render(rule["response"], buyer=buyer))
                return

    async def stock_text(self) -> str:
        products = [p for p in await db.products(self.tg_id) if p["enabled"]]
        if not products:
            return "Сейчас товаров в наличии нет."
        lines = ["📦 Наличие товаров:"]
        for p in products:
            per = max(1, p["per_payment"] or 1)
            lines.append(f"• {p['name']} — {p['stock_count'] // per} шт. ({p['price']:g} ₽)")
        return "\n".join(lines)


class EngineManager:
    def __init__(self) -> None:
        self.engines: dict[int, Engine] = {}
        self.bot: Bot | None = None

    def get(self, tg_id: int) -> Engine | None:
        return self.engines.get(tg_id)

    async def start(self, tg_id: int, token: str) -> Engine:
        await self.stop(tg_id)
        engine = Engine(tg_id, token, self.bot)
        await engine.start()
        self.engines[tg_id] = engine
        return engine

    async def stop(self, tg_id: int) -> None:
        engine = self.engines.pop(tg_id, None)
        if engine:
            await engine.stop()

    async def start_all(self) -> None:
        for user in await db.connected_users():
            try:
                await self.start(user["tg_id"], user["token"])
            except Exception as exc:
                log.warning("Не удалось запустить движок %s: %s", user["tg_id"], exc)

    async def stop_all(self) -> None:
        for tg_id in list(self.engines):
            await self.stop(tg_id)


manager = EngineManager()
