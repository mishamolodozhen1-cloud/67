from __future__ import annotations

from .base import ParseResult, Plugin


class TextPlugin(Plugin):
    key = "text"
    title = "Универсальный (ключи, ссылки, текст)"
    emoji = "📝"
    input_help = (
        "Каждая строка — отдельная единица товара (ключ, ссылка, логин:пароль и т.д.).\n"
        "Можно прислать текстом или .txt файлом."
    )

    def parse(self, text: str) -> ParseResult:
        result = ParseResult()
        seen: set[str] = set()
        for line in text.splitlines():
            line = line.strip()
            if not line:
                continue
            if line in seen:
                result.duplicates += 1
                continue
            seen.add(line)
            result.entries.append(line)
        return result

    def format_unit(self, entry: str, index: int) -> str:
        return f"{index}. {entry}"

    def format_goods(self, entries: list[str]) -> str:
        return "\n".join(self.format_unit(e, i) for i, e in enumerate(entries, 1))

    def preview(self, entry: str) -> str:
        return entry if len(entry) <= 6 else entry[:4] + "•••" + entry[-2:]
