# CF mod kit (CounterFlame v1.4.1-c7)

Полный инжект: нативный overlay-мод + smali-лоадер + EAS-лаунчер.
Меню тёмное, тёплое — gun-metal фон, brass акцент, без неона.

## Что внутри

- `native/` — libcfcheat.so: GLES3-меню, тач-бридж, Il2Cpp SDK, все читы.
- `smali-patch/` — OverlayService + Bridge (Java → native touch feed).
- `scripts/` — инжектор, апи-патчер, сборочный pipeline.
- `launcher/` — Expo RN app (`CF Bench`), скачивает/ставит собранный APK,
  собирается в облаке через EAS по токену `EXPO_TOKEN`.

## Читы

| вкладка | что                                                     |
|--------:|----------------------------------------------------------|
| ESP     | enemy, bounding box, name, hp bar, tracers              |
| Aim     | assist с FOV + smooth + выбор кости (head/neck/chest)   |
| Move    | fly, fly speed, noclip                                  |
| Skins   | локальный skin changer, 8 пресетов                      |
| World   | kill all enemies (arm → fire)                           |
| Misc    | god mode, rapid fire, no spread, speedhack, wallbang    |

## Сборка APK мода (локально)

Требования: Android NDK r26b+, Android SDK build-tools 34+, apktool 2.9+,
baksmali, d8, python3, keytool, ~5 GB свободного места на диск.

```bash
export ANDROID_NDK_HOME=~/Android/Sdk/ndk/26.2.11394342
export ANDROID_HOME=~/Android/Sdk
bash cf-mod/scripts/build.sh
```

На выходе: `cf-mod/build/CounterFlame-1.4.1-c7-mod.apk` — ставь, запускай,
FAB с двумя чёрточками по центру экрана открывает меню.

## Сборка APK лаунчера (облако через EAS)

```bash
cd cf-mod/launcher
cp .env.example .env   # вставь туда свой EXPO_TOKEN
npm install
bash build-apk.sh
```

В выводе появится ссылка на готовый `.apk`.
