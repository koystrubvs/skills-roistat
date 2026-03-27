# koystrubvs-skills

Маркетплейс плагинов для Claude Cowork.

## Установка

В настройках Cowork → Plugins → Add Marketplace:
```
koystrubvs/skills-roistat
```

## Плагины

| Plugin | Description |
|--------|-------------|
| **roistat** | Сквозная аналитика Roistat: проекты, каналы, визиты, лиды, продажи, ROI, звонки |

## Добавление нового плагина

1. Создать папку `plugins/<plugin-name>/`
2. Добавить `.claude-plugin/plugin.json` с метаданными
3. Добавить `skills/<skill-name>/SKILL.md` с инструкциями
4. Добавить скрипты в `skills/<skill-name>/scripts/`
