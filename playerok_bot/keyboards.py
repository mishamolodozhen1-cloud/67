"""Кнопки бота. Цвет задаётся полем style (Bot API 9.4+):
"success" — зелёная, "primary" — синяя."""

from __future__ import annotations

from aiogram.types import InlineKeyboardButton, InlineKeyboardMarkup

GREEN = "success"
BLUE = "primary"


def btn(text: str, cb: str | None = None, style: str = BLUE, *, url: str | None = None) -> InlineKeyboardButton:
    if url:
        return InlineKeyboardButton(text=text, url=url, style=style)
    return InlineKeyboardButton(text=text, callback_data=cb, style=style)


def kb(rows: list[list[InlineKeyboardButton]]) -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup(inline_keyboard=rows)


def toggle(label: str, on: bool, cb: str) -> InlineKeyboardButton:
    """Переключатель: включён — зелёный, выключен — синий."""
    return btn(f"{'🟢' if on else '⚪️'} {label}", cb, GREEN if on else BLUE)


def back(cb: str = "menu", text: str = "⬅️ Назад") -> list[InlineKeyboardButton]:
    return [btn(text, cb, BLUE)]


def main_menu() -> InlineKeyboardMarkup:
    return kb(
        [
            [btn("📦 Мои товары", "products", BLUE), btn("📥 Загрузить с Playerok", "pk_items:0", GREEN)],
            [btn("💬 Автоответчик", "ar", BLUE), btn("🤝 Сделки", "deals", GREEN)],
            [btn("📊 Статистика", "stats", GREEN), btn("💰 Баланс", "balance", BLUE)],
            [btn("⚙️ Настройки", "settings", BLUE), btn("🔄 Обновить", "menu", GREEN)],
        ]
    )


def connect_menu() -> InlineKeyboardMarkup:
    return kb(
        [
            [btn("🔑 Подключить Playerok", "connect", GREEN)],
            [btn("❓ Где взять токен", "token_help", BLUE)],
        ]
    )


def cancel(cb: str = "menu") -> InlineKeyboardMarkup:
    return kb([[btn("✖️ Отмена", cb, BLUE)]])
