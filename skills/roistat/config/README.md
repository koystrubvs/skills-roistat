# Получение API-ключа Roistat

## Шаг 1: Войдите в Roistat

1. Откройте https://cloud.roistat.com
2. Войдите в свой аккаунт

## Шаг 2: Получите API-ключ

1. Перейдите в **Настройки → Интеграции → API**
2. Скопируйте API-ключ (или создайте новый)

## Шаг 3: Настройте токен

```bash
cp config/.env.example config/.env
```

Вставьте ключ:
```
ROISTAT_API_KEY=ваш_ключ_здесь
```

## Проверка

```bash
bash scripts/projects.sh
```

Должен показать список ваших проектов.

## Документация

- Roistat API: https://help-ru.roistat.com/API/methods/about/
