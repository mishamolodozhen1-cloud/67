from aiogram.fsm.state import State, StatesGroup


class Connect(StatesGroup):
    token = State()


class ProductEdit(StatesGroup):
    stock = State()
    per_payment = State()
    delivery_text = State()
    price = State()


class AutoReply(StatesGroup):
    greeting = State()
    triggers = State()
    response = State()


class Reply(StatesGroup):
    text = State()


class Settings(StatesGroup):
    low_stock = State()
