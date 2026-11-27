# DUMMY COMBAT

Многопользовательский FPS для Roblox с физикой тряпичных кукол: манекены сражаются на аренах, пули толкают тела по направлению и месту попадания, после смерти тело падает регдоллом. ПК, Mac, Android, iOS.

Разработка идёт по 12 этапам. Следующий этап начинается только после проверки предыдущего.

| Этап | Что | Статус |
|---|---|---|
| 1 | Фундамент: архитектура, модули, конфиги, журнал, сеть | код готов, сервер проверен; ждёт проверки клиента в Studio |
| 2 | Персонаж-манекен и передвижение | — |
| 3 | Ragdoll | — |
| 4 | FPS и оружие (AK-47) | — |
| 5 | Урон и бой | — |
| 6 | Карта INDUSTRIAL ZONE | — |
| 7 | Мультиплеер и матчи (Free For All) | — |
| 8 | Главное лобби | — |
| 9 | Остальные карты и режимы | — |
| 10 | Прогрессия и экономика | — |
| 11 | Интерфейс и мобильное управление | — |
| 12 | Финальная полировка | — |

## Структура

```
src/
  ReplicatedStorage/
    Shared/                 общий код сервера и клиента
      Logger                журнал: уровни, повторы, история, приёмники
      Signal                события внутри одной стороны
      Maid                  уборка объектов, соединений и потоков одной командой
      Validate              проверка данных от клиента
      RateLimiter           ограничение частоты (ведро с жетонами)
      ModuleLoader          запуск модулей: require → Init → Start
    Configs/
      GameConfig            общие настройки (заморожены)
      RemoteDefinitions     единственный список сетевых событий со схемами и лимитами
      BuildInfo             создаёт сборщик: версия, коммит, время сборки
    Remotes/                сервер создаёт события по RemoteDefinitions
    Assets/                 общие ресурсы (оружие, эффекты, звуки — с этапа 4)
  ServerScriptService/
    Server/Main, Bootstrap  точка входа сервера и запуск сервисов
    Services/
      ErrorService          ошибки сервера, журнала и клиентов в одном месте
      NetService            сеть: создание remotes, проверки, лимиты, нарушения
      PlayerService         сессии игроков, ClientReady → ServerInfo
    Systems/                игровые системы (с этапа 2)
  ServerStorage/            Weapons, Maps, CharacterAssets — то, что клиенту не нужно заранее
  StarterPlayer/
    StarterPlayerScripts/Client/
      Main                  точка входа клиента
      Controllers/
        ErrorReporter       ошибки клиента → сервер
        ClientNet           сеть на клиенте
    StarterCharacterScripts/   (этап 2)
  StarterGui/               MainUI, HUD, Menus — ScreenGui без сброса при смерти
  Workspace/                Lobby, ActiveMap, SpawnLocations
  Lighting/                 освещение Future
```

Изменения относительно схемы из ТЗ:
- `Configs` и `Remotes` лежат в ReplicatedStorage, как и задумано, но `Remotes` в исходниках пустая: объекты в ней создаёт сервер по `RemoteDefinitions`. Так нельзя завести событие без схемы проверки, а посторонние объекты сервер удаляет.
- `Server` — точка входа и загрузчик, `Services` — постоянные сервисы (сеть, ошибки, игроки, позже данные), `Systems` — игровые системы (персонаж, оружие, матчи).
- `StreamingEnabled` выключен: арены небольшие, а проверке попаданий и регдоллам нужен весь мир у каждого игрока. Если карты вырастут, вернёмся к этому на этапе оптимизации.
- `Workspace/SpawnLocations/BootstrapSpawn` — временная точка появления, чтобы до лобби (этап 8) было где появиться. Её уберёт этап 8.

## Правила кода

- Сервер решает всё важное: урон, попадания, награды, результаты. Клиент управляет и показывает.
- Каждое событие от клиента описано в `RemoteDefinitions`: схема аргументов (Validate) и лимит частоты. NetService отбрасывает неверное и считает нарушения; после `ViolationLimit` нарушений за минуту игрока отключает.
- Клиент шлёт реже серверного лимита (`ClientRateFactor`), поэтому честный клиент нарушений не получает.
- Ошибки сервера, журнала и клиентов собирает ErrorService (`GetRecent`).
- Модули — таблицы с `Name`, `Init(context)`, `Start(context)`; другие модули берутся через `context.Get("Имя")`.
- Устаревшие API Roblox запрещены. Линт проверяет `wait/spawn/delay/tick`, `Body*`-моверы, `FindPartOnRay`, `Humanoid:LoadAnimation`, `Instance.new(класс, родитель)` и другие.
- Код пишется без аннотаций типов и `+=`, чтобы его проверял линт.

## Сборка и проверка

```
python3 build.py                     # build/DummyCombat.rbxl + build/manifest.txt
cd tools/lint && npm install && cd ../..
node tools/lint/check.js src         # синтаксис, глобальные переменные, устаревшие API
python3 tools/cloud.py test          # сборка → неопубликованная версия плейса → tests/stage1.test.lua на сервере Roblox
```

`build/DummyCombat.rbxl` можно открыть в Roblox Studio напрямую.

### Проверка в Studio (клиентская часть этапа 1)

На безголовом сервере Open Cloud нет живого клиента, поэтому клиент проверяется в Studio. Откройте `build/DummyCombat.rbxl` и нажмите Play. В Output должно появиться:

```
[DC S][INFO][Boot] DUMMY COMBAT 0.1.0 (сборка …)
[DC S][INFO][Server] запущено за … ErrorService=Started, NetService=Started, PlayerService=Started
[DC S][INFO][Players] вошёл <ник> …
[DC C][INFO][Client] запущено за … ErrorReporter=Started, ClientNet=Started
[DC C][INFO][Net] сервер: DUMMY COMBAT 0.1.0 (сборка …)
[DC S][INFO][Players] <ник> готов (загрузка … с)
```

Красных ошибок быть не должно.

## Плейс

Своего плейса у DUMMY COMBAT пока нет. Тесты сохраняют неопубликованные версии в общий плейс проекта, где опубликована NIGHT SHIFT; опубликованная игра от этого не меняется. Для публикации нужен отдельный плейс: `DC_PLACE_ID=… DC_UNIVERSE_ID=… python3 tools/cloud.py save build/DummyCombat.rbxl publish`. Без своего `DC_PLACE_ID` публикация запрещена.
