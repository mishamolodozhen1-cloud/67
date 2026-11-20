"""Хранилище на SQLite: пользователи, товары, склад, автоответы, сделки."""

from __future__ import annotations

import asyncio
import os
import time
from typing import Any

import aiosqlite

import config

SCHEMA = """
CREATE TABLE IF NOT EXISTS users (
    tg_id            INTEGER PRIMARY KEY,
    token            TEXT,
    pk_user_id       TEXT,
    pk_username      TEXT,
    connected_at     REAL,
    auto_delivery    INTEGER DEFAULT 1,
    auto_complete    INTEGER DEFAULT 1,
    autoreply        INTEGER DEFAULT 1,
    greeting_on      INTEGER DEFAULT 1,
    greeting_text    TEXT DEFAULT 'Здравствуйте, {buyer}! 👋 Товар выдаётся автоматически сразу после оплаты. Команда !наличие покажет, что сейчас есть в наличии.',
    notify_messages  INTEGER DEFAULT 1,
    notify_deals     INTEGER DEFAULT 1,
    stock_command    INTEGER DEFAULT 1,
    low_stock        INTEGER DEFAULT 3
);

CREATE TABLE IF NOT EXISTS products (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    tg_id            INTEGER NOT NULL,
    item_id          TEXT NOT NULL,
    item_slug        TEXT,
    name             TEXT,
    price            REAL DEFAULT 0,
    plugin           TEXT DEFAULT 'gmail',
    per_payment      INTEGER DEFAULT 1,
    enabled          INTEGER DEFAULT 1,
    auto_relist      INTEGER DEFAULT 0,
    auto_disable     INTEGER DEFAULT 0,
    delivery_text    TEXT,
    created_at       REAL,
    UNIQUE(tg_id, item_id)
);

CREATE TABLE IF NOT EXISTS stock (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    product_id       INTEGER NOT NULL,
    data             TEXT NOT NULL,
    status           TEXT DEFAULT 'available',
    deal_id          TEXT,
    added_at         REAL,
    sold_at          REAL
);
CREATE INDEX IF NOT EXISTS ix_stock_product ON stock(product_id, status);

CREATE TABLE IF NOT EXISTS autoreplies (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    tg_id            INTEGER NOT NULL,
    triggers         TEXT NOT NULL,
    response         TEXT NOT NULL,
    exact            INTEGER DEFAULT 0
);

CREATE TABLE IF NOT EXISTS deals (
    deal_id          TEXT PRIMARY KEY,
    tg_id            INTEGER NOT NULL,
    product_id       INTEGER,
    item_name        TEXT,
    buyer            TEXT,
    chat_id          TEXT,
    amount           REAL DEFAULT 0,
    qty              INTEGER DEFAULT 0,
    status           TEXT,
    created_at       REAL
);

CREATE TABLE IF NOT EXISTS greeted_chats (
    tg_id            INTEGER NOT NULL,
    chat_id          TEXT NOT NULL,
    PRIMARY KEY (tg_id, chat_id)
);
"""

USER_TOGGLES = (
    "auto_delivery",
    "auto_complete",
    "autoreply",
    "greeting_on",
    "notify_messages",
    "notify_deals",
    "stock_command",
)
PRODUCT_TOGGLES = ("enabled", "auto_relist", "auto_disable")


class Database:
    def __init__(self, path: str = config.DB_PATH) -> None:
        self.path = path
        self.conn: aiosqlite.Connection | None = None
        self._stock_lock = asyncio.Lock()

    async def connect(self) -> None:
        os.makedirs(os.path.dirname(self.path) or ".", exist_ok=True)
        self.conn = await aiosqlite.connect(self.path)
        self.conn.row_factory = aiosqlite.Row
        await self.conn.executescript(SCHEMA)
        await self.conn.commit()

    async def close(self) -> None:
        if self.conn:
            await self.conn.close()

    # --- низкоуровневое ------------------------------------------------------

    async def _one(self, sql: str, args: tuple = ()) -> dict[str, Any] | None:
        async with self.conn.execute(sql, args) as cur:
            row = await cur.fetchone()
        return dict(row) if row else None

    async def _all(self, sql: str, args: tuple = ()) -> list[dict[str, Any]]:
        async with self.conn.execute(sql, args) as cur:
            rows = await cur.fetchall()
        return [dict(r) for r in rows]

    async def _exec(self, sql: str, args: tuple = ()) -> int:
        cur = await self.conn.execute(sql, args)
        await self.conn.commit()
        return cur.lastrowid

    # --- пользователи --------------------------------------------------------

    async def get_user(self, tg_id: int) -> dict[str, Any] | None:
        return await self._one("SELECT * FROM users WHERE tg_id=?", (tg_id,))

    async def connected_users(self) -> list[dict[str, Any]]:
        return await self._all("SELECT * FROM users WHERE token IS NOT NULL")

    async def save_token(self, tg_id: int, token: str, pk_user_id: str, pk_username: str) -> None:
        user = await self.get_user(tg_id)
        if user:
            await self._exec(
                "UPDATE users SET token=?, pk_user_id=?, pk_username=?, connected_at=? WHERE tg_id=?",
                (token, pk_user_id, pk_username, time.time(), tg_id),
            )
        else:
            await self._exec(
                "INSERT INTO users (tg_id, token, pk_user_id, pk_username, connected_at) VALUES (?,?,?,?,?)",
                (tg_id, token, pk_user_id, pk_username, time.time()),
            )

    async def logout(self, tg_id: int) -> None:
        await self._exec("UPDATE users SET token=NULL WHERE tg_id=?", (tg_id,))

    async def toggle_user(self, tg_id: int, field: str) -> None:
        if field not in USER_TOGGLES:
            raise ValueError(field)
        await self._exec(f"UPDATE users SET {field}=1-{field} WHERE tg_id=?", (tg_id,))

    async def set_user_field(self, tg_id: int, field: str, value: Any) -> None:
        if field not in ("greeting_text", "low_stock"):
            raise ValueError(field)
        await self._exec(f"UPDATE users SET {field}=? WHERE tg_id=?", (value, tg_id))

    # --- товары --------------------------------------------------------------

    async def add_product(
        self, tg_id: int, item_id: str, slug: str | None, name: str, price: float, plugin: str
    ) -> int:
        existing = await self._one(
            "SELECT id FROM products WHERE tg_id=? AND item_id=?", (tg_id, item_id)
        )
        if existing:
            await self._exec(
                "UPDATE products SET name=?, price=?, item_slug=?, plugin=? WHERE id=?",
                (name, price, slug, plugin, existing["id"]),
            )
            return existing["id"]
        return await self._exec(
            "INSERT INTO products (tg_id, item_id, item_slug, name, price, plugin, created_at) "
            "VALUES (?,?,?,?,?,?,?)",
            (tg_id, item_id, slug, name, price, plugin, time.time()),
        )

    async def get_product(self, product_id: int, tg_id: int | None = None) -> dict[str, Any] | None:
        if tg_id is None:
            return await self._one("SELECT * FROM products WHERE id=?", (product_id,))
        return await self._one("SELECT * FROM products WHERE id=? AND tg_id=?", (product_id, tg_id))

    async def product_by_item(self, tg_id: int, item_id: str) -> dict[str, Any] | None:
        return await self._one(
            "SELECT * FROM products WHERE tg_id=? AND item_id=?", (tg_id, item_id)
        )

    async def product_by_name(self, tg_id: int, name: str) -> dict[str, Any] | None:
        return await self._one(
            "SELECT * FROM products WHERE tg_id=? AND lower(name)=lower(?)", (tg_id, name)
        )

    async def products(self, tg_id: int) -> list[dict[str, Any]]:
        return await self._all(
            "SELECT p.*, (SELECT COUNT(*) FROM stock s WHERE s.product_id=p.id AND s.status='available') AS stock_count, "
            "(SELECT COUNT(*) FROM stock s WHERE s.product_id=p.id AND s.status='sold') AS sold_count "
            "FROM products p WHERE tg_id=? ORDER BY id",
            (tg_id,),
        )

    async def toggle_product(self, product_id: int, field: str) -> None:
        if field not in PRODUCT_TOGGLES:
            raise ValueError(field)
        await self._exec(f"UPDATE products SET {field}=1-{field} WHERE id=?", (product_id,))

    async def set_product_field(self, product_id: int, field: str, value: Any) -> None:
        if field not in ("per_payment", "delivery_text", "plugin", "item_id", "name", "price"):
            raise ValueError(field)
        await self._exec(f"UPDATE products SET {field}=? WHERE id=?", (value, product_id))

    async def delete_product(self, product_id: int) -> None:
        await self._exec("DELETE FROM stock WHERE product_id=?", (product_id,))
        await self._exec("DELETE FROM products WHERE id=?", (product_id,))

    # --- склад ---------------------------------------------------------------

    async def add_stock(self, product_id: int, entries: list[str]) -> int:
        now = time.time()
        await self.conn.executemany(
            "INSERT INTO stock (product_id, data, added_at) VALUES (?,?,?)",
            [(product_id, e, now) for e in entries],
        )
        await self.conn.commit()
        return len(entries)

    async def stock_count(self, product_id: int) -> int:
        row = await self._one(
            "SELECT COUNT(*) AS c FROM stock WHERE product_id=? AND status='available'", (product_id,)
        )
        return row["c"] if row else 0

    async def stock_list(self, product_id: int, status: str = "available") -> list[dict[str, Any]]:
        return await self._all(
            "SELECT * FROM stock WHERE product_id=? AND status=? ORDER BY id", (product_id, status)
        )

    async def existing_stock_data(self, product_id: int) -> set[str]:
        rows = await self._all("SELECT data FROM stock WHERE product_id=?", (product_id,))
        return {r["data"] for r in rows}

    async def take_stock(self, product_id: int, qty: int, deal_id: str) -> list[str] | None:
        """Атомарно забрать qty единиц товара. None — если не хватает."""
        async with self._stock_lock:
            rows = await self._all(
                "SELECT id, data FROM stock WHERE product_id=? AND status='available' ORDER BY id LIMIT ?",
                (product_id, qty),
            )
            if len(rows) < qty:
                return None
            now = time.time()
            await self.conn.executemany(
                "UPDATE stock SET status='sold', deal_id=?, sold_at=? WHERE id=?",
                [(deal_id, now, r["id"]) for r in rows],
            )
            await self.conn.commit()
            return [r["data"] for r in rows]

    async def return_stock(self, deal_id: str) -> int:
        cur = await self.conn.execute(
            "UPDATE stock SET status='available', deal_id=NULL, sold_at=NULL WHERE deal_id=?",
            (deal_id,),
        )
        await self.conn.commit()
        return cur.rowcount

    async def clear_stock(self, product_id: int) -> None:
        await self._exec("DELETE FROM stock WHERE product_id=? AND status='available'", (product_id,))

    # --- автоответы ----------------------------------------------------------

    async def autoreplies(self, tg_id: int) -> list[dict[str, Any]]:
        return await self._all("SELECT * FROM autoreplies WHERE tg_id=? ORDER BY id", (tg_id,))

    async def add_autoreply(self, tg_id: int, triggers: str, response: str, exact: bool) -> int:
        return await self._exec(
            "INSERT INTO autoreplies (tg_id, triggers, response, exact) VALUES (?,?,?,?)",
            (tg_id, triggers, response, int(exact)),
        )

    async def delete_autoreply(self, tg_id: int, rule_id: int) -> None:
        await self._exec("DELETE FROM autoreplies WHERE id=? AND tg_id=?", (rule_id, tg_id))

    # --- сделки --------------------------------------------------------------

    async def deal_known(self, deal_id: str) -> dict[str, Any] | None:
        return await self._one("SELECT * FROM deals WHERE deal_id=?", (deal_id,))

    async def save_deal(self, **fields: Any) -> None:
        fields.setdefault("created_at", time.time())
        keys = ", ".join(fields)
        marks = ", ".join("?" for _ in fields)
        updates = ", ".join(f"{k}=excluded.{k}" for k in fields if k != "deal_id")
        await self._exec(
            f"INSERT INTO deals ({keys}) VALUES ({marks}) ON CONFLICT(deal_id) DO UPDATE SET {updates}",
            tuple(fields.values()),
        )

    async def recent_deals(self, tg_id: int, limit: int = 10) -> list[dict[str, Any]]:
        return await self._all(
            "SELECT * FROM deals WHERE tg_id=? ORDER BY created_at DESC LIMIT ?", (tg_id, limit)
        )

    async def stats(self, tg_id: int) -> dict[str, Any]:
        day = time.time() - 86400
        total = await self._one(
            "SELECT COUNT(*) AS n, COALESCE(SUM(amount),0) AS s, COALESCE(SUM(qty),0) AS q "
            "FROM deals WHERE tg_id=? AND status='delivered'",
            (tg_id,),
        )
        today = await self._one(
            "SELECT COUNT(*) AS n, COALESCE(SUM(amount),0) AS s FROM deals "
            "WHERE tg_id=? AND status='delivered' AND created_at>=?",
            (tg_id, day),
        )
        failed = await self._one(
            "SELECT COUNT(*) AS n FROM deals WHERE tg_id=? AND status IN ('no_stock','error')",
            (tg_id,),
        )
        return {"total": total, "today": today, "failed": failed["n"]}

    # --- приветствия ---------------------------------------------------------

    async def was_greeted(self, tg_id: int, chat_id: str) -> bool:
        return bool(
            await self._one(
                "SELECT 1 FROM greeted_chats WHERE tg_id=? AND chat_id=?", (tg_id, chat_id)
            )
        )

    async def mark_greeted(self, tg_id: int, chat_id: str) -> None:
        await self._exec(
            "INSERT OR IGNORE INTO greeted_chats (tg_id, chat_id) VALUES (?,?)", (tg_id, chat_id)
        )


db = Database()
