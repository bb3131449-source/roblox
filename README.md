# Portal Script

## Описание

Установка: папку portal целиком положить в workspace executor (рядом с portal_saves.json).
Запуск:    loadstring(readfile("portal/main.lua"))()
Настройки: portal/config.lua (звуки, ID ассетов, размеры, тайминги, префикс команд).
Загрузка по URL: BASE_URL в portal/main.lua.

## Запуск

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/bb3131449-source/roblox/main/portal/main.lua"))()
```

## Структура

- `portal/main.lua` — точка входа. При заданном `BASE_URL` подтягивает модули по HTTP
- `portal/*.lua` — модули: `config`, `core`, `helpers`, `sfx`, `queries`, `ui`, `portal`, `gun`, `placement`, `teleport`, `travel`, `place`, `map`, `saves`, `link`, `commands`, `tool`, `session`

## Настройка

Параметры находятся в `portal/config.lua`.
`BASE_URL` в `portal/main.lua` указывает на `https://raw.githubusercontent.com/bb3131449-source/roblox/main/portal`.
`PLACE_RELOAD_SOURCE` указывает на `https://raw.githubusercontent.com/bb3131449-source/roblox/main/portal/main.lua`.
