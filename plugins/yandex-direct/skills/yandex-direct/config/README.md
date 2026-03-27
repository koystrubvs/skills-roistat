# Настройка Yandex Direct API

## Получение OAuth-токена

### Быстрый способ (через браузер)

1. Перейдите по ссылке:
   ```
   https://oauth.yandex.ru/authorize?response_type=token&client_id=764119e8c8be4c39b6e2d3e6e9dab3c2
   ```
2. Авторизуйтесь в Яндексе (под аккаунтом, у которого есть доступ к Директу)
3. Скопируйте `access_token` из URL после редиректа

### Через своё приложение

1. Зарегистрируйте приложение на https://oauth.yandex.ru/client/new
   - Тип: Веб-сервис
   - Права: `direct:api` (Управление рекламными кампаниями)
2. Получите `client_id`
3. Перейдите:
   ```
   https://oauth.yandex.ru/authorize?response_type=token&client_id=ВАШ_CLIENT_ID
   ```
4. Скопируйте токен

## Настройка

Скопируйте `.env.example` в `.env` и укажите токен:

```bash
cp .env.example .env
# Отредактируйте .env
```

```
YANDEX_DIRECT_TOKEN=y0_AgAAAA...ваш_токен
```

## Агентские аккаунты

Если вы работаете через агентский аккаунт, укажите логин рекламодателя:

```
YANDEX_DIRECT_LOGIN=advertiser_login
```

Или передайте при вызове скрипта: `--login advertiser_login`
