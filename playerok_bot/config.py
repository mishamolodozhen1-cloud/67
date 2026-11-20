"""Настройки бота. Любое значение можно переопределить переменной окружения."""

import os

# Токен Telegram-бота (по просьбе владельца прописан прямо в коде).
BOT_TOKEN = os.getenv("BOT_TOKEN", "9078871270:AAGHlrSv1Ykwop0L0eXP9pIJeH3hbguqHZE")

# Telegram ID, которым разрешено пользоваться ботом (через запятую).
# Пусто — бот доступен всем, и каждый подключает свой аккаунт Playerok.
OWNER_IDS = {int(x) for x in os.getenv("OWNER_IDS", "").replace(" ", "").split(",") if x}

# Файл базы данных SQLite.
DB_PATH = os.getenv("DB_PATH", os.path.join(os.path.dirname(__file__), "data", "bot.db"))

# Интервалы опроса Playerok (секунды).
DEALS_POLL_INTERVAL = float(os.getenv("DEALS_POLL_INTERVAL", "12"))
CHATS_POLL_INTERVAL = float(os.getenv("CHATS_POLL_INTERVAL", "8"))

# Максимальная длина одного сообщения в чате Playerok.
PLAYEROK_MSG_LIMIT = int(os.getenv("PLAYEROK_MSG_LIMIT", "1800"))

# Прокси для запросов к Playerok (например http://user:pass@host:port), если нужен.
PLAYEROK_PROXY = os.getenv("PLAYEROK_PROXY") or None
