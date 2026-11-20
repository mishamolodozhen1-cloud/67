from __future__ import annotations

from dataclasses import dataclass, field


@dataclass
class ParseResult:
    entries: list[str] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)
    duplicates: int = 0


class Plugin:
    key = "base"
    title = "Плагин"
    emoji = "🧩"
    unit = "шт."
    input_help = ""

    def parse(self, text: str) -> ParseResult:
        raise NotImplementedError

    def format_unit(self, entry: str, index: int) -> str:
        raise NotImplementedError

    def preview(self, entry: str) -> str:
        """Короткое (замаскированное) представление единицы для Telegram."""
        raise NotImplementedError

    def format_goods(self, entries: list[str]) -> str:
        return "\n\n".join(self.format_unit(e, i) for i, e in enumerate(entries, 1))
