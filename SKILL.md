---
name: roistat
description: |
  Сквозная аналитика Roistat: проекты, каналы, визиты, лиды, продажи, ROI, звонки, расходы.
  Cache-first подход для гигиены контекстного окна.
  ОБЯЗАТЕЛЬНО используй этот скилл при любом упоминании Roistat, сквозной аналитики, ROI рекламы, коллтрекинга Roistat, лидов из Roistat.
  Triggers: roistat, роистат, сквозная аналитика, roi рекламы, коллтрекинг, лиды roistat, расходы на рекламу roistat.
---

# roistat

Работа с Roistat API v1. Сквозная аналитика: визиты, лиды, продажи, ROI, расходы, звонки по рекламным каналам.

## Config

Требуется `ROISTAT_API_KEY` в `config/.env`.
Инструкция: `config/README.md`.

## Philosophy

1. **Cache-first** — список проектов, источников, метрик кешируются надолго. Отчёты кешируются по ключу project+dates+params. Перед API-запросом всегда проверяем кеш.
2. **Context window hygiene** — stdout ограничен 30 строками. Полные данные в TSV/файл. Кеш доступен через grep/rg.
3. **Project resolution** — все скрипты принимают `--project <ID>`. Первый вызов projects.sh кеширует список.

## Workflow

### STOP! Перед любым анализом:

1. **Получи список проектов:**
   ```bash
   bash scripts/projects.sh
   ```

2. **Спроси пользователя** (если проект не очевиден из контекста):
   ```
   "О каком проекте идёт речь?
   Укажите ID или название из списка."
   ```
   Для поиска по кешу:
   ```bash
   bash scripts/projects.sh --search "sugar"
   ```

3. **Запускай отчёты** по задаче пользователя.

## Scripts

| Script | Description | Key params |
|--------|-------------|------------|
| `projects.sh` | Список проектов | `--search "text"`, `--no-cache` |
| `analytics.sh` | Основной отчёт: каналы, визиты, лиды, продажи, ROI | `--dimension`, `--metrics`, `--interval` |
| `sources.sh` | Рекламные каналы/источники | — |
| `metrics.sh` | Доступные метрики проекта | — |
| `calls.sh` | Аналитика звонков по каналам | `--interval` |

## Общие параметры

| Param | Required | Default | Description |
|-------|----------|---------|-------------|
| `--project` | yes | - | ID проекта |
| `--date-from` | yes* | - | Начало периода YYYY-MM-DD |
| `--date-to` | no | today | Конец периода YYYY-MM-DD |
| `--dimension` | no | marker_level_1 | Группировка: marker_level_1, marker_level_2, ... |
| `--metrics` | no | visits,leads,sales,revenue,marketing_cost,roi,cpl,conversion_visits_to_leads | Метрики через запятую |
| `--interval` | no | - | Разбивка по времени: 1d, 1w, 1m |
| `--no-cache` | no | - | Пропустить кеш |
| `--csv` | no | - | Путь для CSV экспорта |

\* не требуется для projects.sh, sources.sh, metrics.sh

## Популярные метрики

| Metric | Description |
|--------|-------------|
| visits | Визиты |
| leads | Заявки |
| sales | Продажи |
| revenue | Выручка |
| marketing_cost | Расходы на рекламу |
| roi | ROI |
| cpl | Стоимость лида |
| cpc | Стоимость клика |
| conversion_visits_to_leads | Конверсия визитов в заявки (%) |
| conversion_leads_to_sales | Конверсия заявок в продажи (%) |
| calls | Звонки |
| uniqueCalls | Уникальные звонки |
| missedCalls | Пропущенные звонки |
| bounce_rate | Показатель отказов |

## Популярные dimensions

| Dimension | Description |
|-----------|-------------|
| marker_level_1 | Канал (верхний уровень) |
| marker_level_2 | Кампания |
| marker_level_3 | Группа объявлений |
| marker_level_4 | Ключевое слово |
| landing_page | Посадочная страница |
| region | Регион |

## Кеш-стратегия

Кеш в `cache/`:
- `projects.tsv` — все проекты (permanent)
- `project_<id>/sources.tsv` — каналы
- `project_<id>/metrics.tsv` — метрики
- `project_<id>/reports/*.tsv` — результаты отчётов (session, hash-keyed)

## Примеры использования

### Отчёт по каналам за март
```bash
bash scripts/analytics.sh --project 285542 --date-from 2026-03-01
```

### Помесячная динамика
```bash
bash scripts/analytics.sh --project 285542 --date-from 2025-01-01 --interval 1m
```

### Звонки по каналам
```bash
bash scripts/calls.sh --project 285542 --date-from 2026-03-01
```

### По посадочным страницам
```bash
bash scripts/analytics.sh --project 285542 --date-from 2026-03-01 --dimension landing_page
```
