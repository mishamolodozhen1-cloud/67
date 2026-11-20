"""Плагин «Gmail аккаунты».

Принимает строки вида:
    почта:пароль
    почта:пароль:резервная_почта_или_телефон
    почта|пароль|резерв|доп.данные   (разделители  :  ;  |  таб  пробел)
"""

from __future__ import annotations

import json
import re

from .base import ParseResult, Plugin

EMAIL_RE = re.compile(r"^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$")
GMAIL_DOMAINS = {"gmail.com", "googlemail.com"}


def _split(line: str) -> list[str]:
    for sep in ("|", ";", "\t"):
        if sep in line:
            return [p.strip() for p in line.split(sep)]
    if ":" in line:
        return [p.strip() for p in line.split(":")]
    return line.split()


class GmailPlugin(Plugin):
    key = "gmail"
    title = "Gmail аккаунты"
    emoji = "📧"
    input_help = (
        "Отправьте аккаунты — по одному на строку:\n"
        "<code>почта:пароль</code>\n"
        "<code>почта:пароль:резервная_почта</code>\n"
        "<code>почта|пароль|резерв|доп.инфо</code>\n\n"
        "Разделители: <code>:</code> <code>;</code> <code>|</code> или пробел. "
        "Можно прислать текстом или .txt файлом."
    )

    def parse(self, text: str) -> ParseResult:
        result = ParseResult()
        seen: set[str] = set()
        for num, raw in enumerate(text.splitlines(), 1):
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            parts = [p for p in _split(line) if p != ""]
            if len(parts) < 2:
                result.errors.append(f"Строка {num}: нет пароля — «{line[:40]}»")
                continue
            email = parts[0].lower()
            if not EMAIL_RE.match(email):
                result.errors.append(f"Строка {num}: неверная почта — «{parts[0][:40]}»")
                continue
            if email.split("@", 1)[1] not in GMAIL_DOMAINS:
                result.errors.append(f"Строка {num}: не Gmail — «{email}»")
                continue
            if email in seen:
                result.duplicates += 1
                continue
            seen.add(email)
            account = {
                "email": email,
                "password": parts[1],
                "recovery": parts[2] if len(parts) > 2 else "",
                "extra": " | ".join(parts[3:]) if len(parts) > 3 else "",
            }
            result.entries.append(json.dumps(account, ensure_ascii=False))
        return result

    @staticmethod
    def load(entry: str) -> dict:
        try:
            data = json.loads(entry)
            if isinstance(data, dict):
                return data
        except (ValueError, TypeError):
            pass
        parts = _split(entry)
        return {
            "email": parts[0] if parts else entry,
            "password": parts[1] if len(parts) > 1 else "",
            "recovery": parts[2] if len(parts) > 2 else "",
            "extra": "",
        }

    @staticmethod
    def key_of(entry: str) -> str:
        return GmailPlugin.load(entry).get("email", "")

    def format_unit(self, entry: str, index: int) -> str:
        acc = self.load(entry)
        lines = [
            f"📧 Аккаунт №{index}",
            f"Почта: {acc.get('email', '')}",
            f"Пароль: {acc.get('password', '')}",
        ]
        if acc.get("recovery"):
            label = "Резервная почта" if "@" in acc["recovery"] else "Резерв"
            lines.append(f"{label}: {acc['recovery']}")
        if acc.get("extra"):
            lines.append(f"Доп.: {acc['extra']}")
        return "\n".join(lines)

    def preview(self, entry: str) -> str:
        acc = self.load(entry)
        email = acc.get("email", "")
        name, _, domain = email.partition("@")
        masked = (name[:3] + "•••" if len(name) > 3 else name) + "@" + domain
        rec = " +резерв" if acc.get("recovery") else ""
        return masked + rec
