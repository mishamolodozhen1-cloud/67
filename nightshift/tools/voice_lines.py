#!/usr/bin/env python3
"""Реплики NIGHT SHIFT для озвучки (v10).

Каждая реплика: ключ -> (текст, текст для женского голоса или None, «нервная» ли (быстрее и выше)).
Покупатели озвучены тремя голосами (M1, M2 — мужские, F1 — женский); у каждого покупателя свой голос
и своя высота тона, поэтому они звучат по-разному. Охранник (игрок) — отдельный голос P.

v11: озвучено в ElevenLabs (eleven_v4). Подача каждой реплики — теги TAGS/PLAYER_TAGS (их читает модель,
вслух они не звучат). Сценарии для ElevenLabs печатает tools/eleven_scripts.py, нарезка — tools/voice_split.py,
сборка спрайтов — tools/voices.py --reuse. (До v11 — синтез Piper, tools/voices.py без --reuse.)
"""

# Покупатели ------------------------------------------------------------------
CUSTOMER = {
    # приветствие у входа
    "Greet1": ("Добрый вечер.", None, False),
    "Greet2": ("Здравствуйте.", None, False),
    "Greet3": ("Ночь сегодня тихая…", None, False),
    "Greet4": ("О, открыто. Отлично.", None, False),
    # пока ходит по рядам
    "Shop1": ("Так… хлеб, молоко…", None, False),
    "Shop2": ("Ничего себе цены.", None, False),
    "Shop3": ("Что бы ещё взять…", None, False),
    "Shop4": ("Где тут у них молоко?", None, False),
    # нет товара
    "Empty1": ("Хм… а тут пусто.", None, False),
    "Empty2": ("А где товар?", None, False),
    # ждёт / торопит
    "Wait1": ("Есть кто на кассе?", None, False),
    "Wait2": ("Ну долго ещё?", None, False),
    "Wait3": ("Кассир! Вы где?", None, False),
    "Wait4": ("Мне бы оплатить…", None, False),
    # спасибо / до свидания
    "Thanks1": ("Спасибо!", None, False),
    "Thanks2": ("Спасибо, хорошей смены.", None, False),
    "Thanks3": ("Благодарю.", None, False),
    "Thanks4": ("До свидания.", None, False),
    "Thanks5": ("Спасибо, а то я уже испугался.", "Спасибо, а то я уже испугалась.", False),
    "Thanks6": ("Отлично, спасибо.", None, False),
    # недоволен
    "Angry1": ("Ну и обслуживание у вас…", None, False),
    "Angry2": ("Ладно, пойду в другой магазин.", None, False),
    "Angry3": ("Безобразие.", None, False),
    "Angry4": ("Ну и магазин…", None, False),
    "Angry5": ("Ладно, не буду ничего брать.", None, False),
    "Angry6": ("Сами разбирайтесь со своей кассой.", None, False),
    "Angry7": ("Ну и ладно. Уйду без покупок.", None, False),
    # касса зовёт сотрудника
    "Help1": ("Тут есть кто-нибудь?", None, False),
    "Help2": ("Касса не работает…", None, False),
    "Help3": ("Позовите кого-нибудь!", None, True),
    "NoPower": ("Без света тут ничего не работает…", None, False),
    # заказ
    "Order1": ("Здравствуйте, я за заказом.", None, False),
    "Order2": ("Добрый вечер, мне заказ забрать.", None, False),
    "Order3": ("Мне бы заказ забрать…", None, False),
    "Order4": ("Есть кто на выдаче?", None, False),
    "Order5": ("Это не мой заказ.", None, False),
    "Order6": ("Ладно, заберу завтра.", None, False),
    "Order7": ("Долго у вас тут…", None, False),
    # пойман у ворот / проверка чека
    "Caught1": ("Ладно, ладно! Вот, забирайте…", None, True),
    "Caught2": ("Я… я просто забыл заплатить.", "Я… я просто забыла заплатить.", True),
    "Caught3": ("Только полицию не вызывайте!", None, True),
    "Check1": ("Вот мой чек. Наверное, метку забыли снять.", None, False),
    "Check2": ("Вы что, меня подозреваете? Вот чек.", None, False),
    "Check3": ("Я всё оплатил. Ну и магазин.", "Я всё оплатила. Ну и магазин.", False),
    # странные покупатели
    "Weird1": ("До завтра. Вернее… до сегодня.", None, False),
    "Weird2": ("Вы тоже здесь работаете?.. Давно?", None, False),
    # свет погас (v10)
    "Dark1": ("Ой! Что случилось?", None, True),
    "Dark2": ("Свет выключили?!", None, True),
    "Dark3": ("Эй! Включите свет!", None, True),
    "Dark4": ("Мне очень страшно…", None, True),
    "Dark5": ("Что вообще происходит?", None, True),
    "Dark6": ("Эй! Кто здесь?!", None, True),
    "Dark7": ("Тут кто-то есть… в темноте.", None, True),
    "Dark8": ("Я ухожу отсюда!", None, True),
    "Dark9": ("Не подходи!", None, True),
    "Dark10": ("Ничего не видно…", None, True),
    # свет снова горит
    "Light1": ("Фух… включили.", None, False),
    "Light2": ("Ну наконец-то.", None, False),
    "Light3": ("Что это вообще было?", None, False),
    # увидел существо
    "Beast1": ("Что это такое?!", None, True),
    "Beast2": ("Там что-то есть!", None, True),
    "Beast3": ("Бегите отсюда!", None, True),
}

# Охранник (игрок) -------------------------------------------------------------
PLAYER = {
    "Start1": "Ну что, ещё одна ночная смена.",
    "Start2": "Так. Камеры, обход, кассы. Поехали.",
    "Start3": "Только бы сегодня было тихо.",
    "Delivery1": "Поставка? В такое время?",
    "Delivery2": "Ладно, отнесу на склад.",
    "Back1": "Не люблю этот склад.",
    "Back2": "Здесь всегда так холодно…",
    "Saw1": "Что… что это было?!",
    "Saw2": "Мне это показалось?",
    "Saw3": "Это не человек…",
    "Saw4": "Так. Спокойно. Просто дыши.",
    "Scared1": "Чёрт! Чёрт-чёрт-чёрт…",
    "Scared2": "Оно было прямо передо мной…",
    "Dark1": "Опять свет вырубило.",
    "Dark2": "Где этот щиток…",
    "Dark3": "Отлично. Просто отлично.",
    "Dark4": "Спокойно, сейчас свет дадут.",
    "Calm1": "Всё в порядке, сохраняйте спокойствие!",
    "Light1": "Наконец-то.",
    "Light2": "Фух, обошлось.",
    "Noise1": "Эй, кто здесь?",
    "Noise2": "Эй! Есть тут кто?",
    "Thief1": "Стоять! Охрана магазина.",
    "Late1": "Ещё чуть-чуть до утра.",
}

# Голоса: модель Piper, скорость (length_scale: меньше — быстрее), сдвиг тона в полутонах
VOICES = {
    "M1": {"model": "ru_RU-denis-medium", "length": 1.0, "semitones": 0.0},
    "M2": {"model": "ru_RU-dmitri-medium", "length": 1.0, "semitones": -0.5},
    "F1": {"model": "ru_RU-irina-medium", "length": 1.0, "semitones": 0.0},
    "P": {"model": "ru_RU-ruslan-medium", "length": 1.02, "semitones": 0.0},
}

# Подача реплик для ElevenLabs v4 (теги в квадратных скобках); нет тега — спокойно ([calm])
TAGS = {
    "Shop2": "[surprised]",
    "Shop3": "[thoughtfully]",
    "Empty1": "[puzzled]",
    "Empty2": "[surprised]",
    "Wait1": "[impatient]",
    "Wait2": "[annoyed]",
    "Wait3": "[impatient]",
    "Wait4": "[tired]",
    "Thanks5": "[relieved]",
    "Angry1": "[annoyed]",
    "Angry2": "[annoyed]",
    "Angry3": "[angry]",
    "Angry4": "[annoyed]",
    "Angry5": "[annoyed]",
    "Angry6": "[angry]",
    "Angry7": "[sighs]",
    "Help1": "[nervous]",
    "Help2": "[nervous]",
    "Help3": "[shouting]",
    "NoPower": "[tired]",
    "Order5": "[puzzled]",
    "Order6": "[annoyed]",
    "Order7": "[annoyed]",
    "Caught1": "[nervous] [breathless]",
    "Caught2": "[nervous]",
    "Caught3": "[scared]",
    "Check1": "[calm]",
    "Check2": "[offended]",
    "Check3": "[annoyed]",
    "Weird1": "[slowly] [deep voice]",
    "Weird2": "[slowly] [softly]",
    "Dark1": "[gasps] [scared]",
    "Dark2": "[scared]",
    "Dark3": "[shouting]",
    "Dark4": "[trembling voice]",
    "Dark5": "[scared]",
    "Dark6": "[shouting] [scared]",
    "Dark7": "[whispers] [scared]",
    "Dark8": "[panicked]",
    "Dark9": "[shouting] [terrified]",
    "Dark10": "[nervous]",
    "Light1": "[exhales] [relieved]",
    "Light2": "[relieved]",
    "Light3": "[confused]",
    "Beast1": "[terrified]",
    "Beast2": "[shouting] [terrified]",
    "Beast3": "[shouting] [panicked]",
}

PLAYER_TAGS = {
    "Start1": "[tired]",
    "Start2": "[tired]",
    "Start3": "[sighs]",
    "Delivery1": "[surprised]",
    "Delivery2": "[tired]",
    "Back1": "[nervous] [softly]",
    "Back2": "[softly]",
    "Saw1": "[trembling voice]",
    "Saw2": "[whispers]",
    "Saw3": "[whispers] [scared]",
    "Saw4": "[breathless]",
    "Scared1": "[panicked] [breathless]",
    "Scared2": "[trembling voice]",
    "Dark1": "[annoyed]",
    "Dark2": "[nervous]",
    "Dark3": "[sarcastic]",
    "Dark4": "[calm]",
    "Calm1": "[shouting]",
    "Light1": "[relieved]",
    "Light2": "[exhales]",
    "Noise1": "[nervous]",
    "Noise2": "[shouting]",
    "Thief1": "[shouting]",
    "Late1": "[tired]",
}

# Голоса ElevenLabs (из библиотеки голосов)
ELEVEN_VOICES = {
    "M1": ("RjY1wx8VeYo2R2WFDXfX", "Kup - Natural Russian YouTube Voice"),
    "M2": ("pbmtwylSjrg30q2xSLkh", "Andrii"),
    "F1": ("Fy6bUBXCIVErEtK9FN5d", "Liubava - Low, mature female voice"),
    "P": ("BQ8zKfpkxw79bVmxuCXa", "Dzmitry - Expressive Russian Narrator"),
}

# Герой во вступительной кат-сцене (v12): молодой мужчина едет на первую ночную смену.
# Голос — тот же, что у охранника в игре (P, ElevenLabs Dzmitry): спокойный, немного уставший.
# ключ -> (текст, подача)
HERO = {
    "Ride1": ("Ну что... Первая смена. Надеюсь, всё пройдёт спокойно.", "[tired] [softly]"),
    "Ride2": ("Главное, чтобы народу ночью было поменьше...", "[sighs]"),
    "Road1": ("Чёрт, ну и погода сегодня...", "[annoyed]"),
    "Road2": ("Интересно, почему они вообще поставили меня именно на ночную смену?", "[thoughtfully]"),
    "Radio1": ("Алло? Ну давай, только не сейчас...", "[frustrated]"),
    "Radio2": ("Ладно, тишина так тишина.", "[sighs]"),
    "Store1": ("Ага, вот и он. Март двадцать четыре...", "[tired]"),
    "Store2": ("Выглядит не особо уютно, конечно.", "[calm]"),
    "Stop1": ("Так, приехали.", "[exhales]"),
    "Msg1": ("Ключи у входа... Инструкции на стойке... Ну, вроде ничего сложного.", "[reading quietly]"),
    "Msg2": ("Ладно, пошли работать.", "[calm]"),
    "Odd1": ("...Так. Это ещё что было?", "[cautiously]"),
    "Odd2": ("Показалось, наверное.", "[unsure]"),
    "Odd3": ("Да уж. Надо было дома поспать.", "[tired] [sighs]"),
}

# Командная кат-сцена (v15): четверо друзей едут на первую смену. Роль -> голос ElevenLabs.
#   TD — водитель (заводила, шутит), TP — пассажир спереди (спокойный, рассудительный),
#   TL — сзади слева (тревожный, замечает странности), TR — сзади справа (весёлый).
# Реплики под 2, 3 и 4 игроков разложены по ролям по-разному (Shared/TeamLines.Script);
# здесь — все варианты, которые нужно озвучить. ключ -> (текст, подача)
TEAM = {
    "TD": {
        "Ready": ("Ну что, мужики, готовы к первой смене?", "[cheerfully]"),
        "Ready2": ("Ну что, готов к первой смене?", "[cheerfully]"),
        "Relax": ("Да ладно вам. Посидим, зарплату получим и домой.", "[laughs]"),
        "Relax2": ("Да ладно тебе. Посидим, зарплату получим и домой.", "[laughs]"),
        "Popular": ("Может, магазин настолько популярный, что одного охранника не хватает?", "[joking]"),
        "Hope": ("Надеюсь, ничего интересного.", "[calm]"),
        "Radio": ("Да что за радио сегодня...", "[annoyed]"),
        "What": ("Что?", "[surprised]"),
        "Arrived": ("Ну вот, приехали.", "[exhales]"),
        "Peculiar": ("Выглядит... своеобразно.", "[unsure]"),
        "LetsGo": ("Ладно, пошли. Не будем опаздывать.", "[calm]"),
        "Jacket": ("Ты куртку дома забыл?", "[teasing]"),
        "Doors": ("О, хоть двери нормальные.", "[amused]"),
        "Stop": ("Да перестань. Мы только пришли.", "[dismissive]"),
    },
    "TP": {
        "Calm": ("Ага. Главное, чтобы ночь спокойно прошла.", "[calm]"),
        "Why2": ("Я вообще не понимаю, зачем нас двоих сюда поставили.", "[thoughtfully]"),
        "Popular": ("Может, магазин настолько популярный, что одного охранника не хватает?", "[joking]"),
        "Know2": ("Кстати, а ты вообще знаешь, что здесь ночью происходит?", "[curious]"),
        "Hope": ("Надеюсь, ничего интересного.", "[calm]"),
        "Off": ("Выключи его уже.", "[tired]"),
        "Saw2": ("Эй... Ты это видел?", "[nervous]"),
        "Nothing": ("Да ничего. Забей.", "[unsure]"),
        "Store": ("Это и есть наш магазин?", "[unsure]"),
        "LetsGo": ("Ладно, пошли. Не будем опаздывать.", "[calm]"),
        "Cold": ("Ну и холодина...", "[shivering]"),
        "Jacket": ("Ты куртку дома забыл?", "[teasing]"),
        "Funny": ("Очень смешно.", "[sarcastic]"),
        "Come": ("Пойдём уже.", "[calm]"),
        "Feel2": ("Слушай... А тебе не кажется, что здесь кто-то есть?", "[whispers]"),
        "Instr": ("Ладно, давайте сначала найдём инструкции.", "[calm]"),
        "Instr2": ("Ладно, давай сначала найдём инструкции.", "[calm]"),
    },
    "TL": {
        "Why3": ("Я вообще не понимаю, зачем нас троих сюда поставили.", "[thoughtfully]"),
        "Why4": ("Я вообще не понимаю, зачем нас четверых сюда поставили.", "[thoughtfully]"),
        "Know": ("Кстати, а кто-нибудь вообще знает, что здесь ночью происходит?", "[curious]"),
        "Saw": ("Эй... Вы это видели?", "[nervous]"),
        "Nothing": ("Да ничего. Забей.", "[unsure]"),
        "Peculiar": ("Выглядит... своеобразно.", "[unsure]"),
        "Cold": ("Ну и холодина...", "[shivering]"),
        "Funny": ("Очень смешно.", "[sarcastic]"),
        "Feel": ("Ребят... А вам не кажется, что здесь кто-то есть?", "[whispers]"),
    },
    "TR": {
        "Popular": ("Может, магазин настолько популярный, что одного охранника не хватает?", "[joking]"),
        "Know": ("Кстати, а кто-нибудь вообще знает, что здесь ночью происходит?", "[curious]"),
        "LetsGo": ("Ладно, пошли. Не будем опаздывать.", "[calm]"),
        "Cold": ("Ну и холодина...", "[shivering]"),
        "Funny": ("Очень смешно.", "[sarcastic]"),
        "Come": ("Пойдём уже.", "[calm]"),
    },
}

TEAM_VOICES = {
    "TD": ("g1G73EpCIdK4HUyDiLYF", "Egor — Young & Energetic"),
    "TP": ("XBfpCafhcwECiDUWdxir", "Said RU"),
    "TL": ("XGyi3FDBCYWBQ6vRd0FV", "EscobarRKZ"),
    "TR": ("Uv3rf12Omd9Asyv54Bqw", "Max - Alive and Emotional"),
}

