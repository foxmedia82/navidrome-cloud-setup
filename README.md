# 🎵 Cloud Music Server Installer

> One-command installer for Navidrome + Cloud Storage + HTTPS

Автоматическая установка **Navidrome** с музыкальной библиотекой, расположенной в облачном хранилище.

Скрипт полностью настраивает сервер "с нуля" и позволяет получить собственный музыкальный стриминговый сервис за несколько минут.

This installer is an unofficial installation script and is not affiliated with the Navidrome, rclone, Caddy or FFmpeg projects.

Этот установщик является неофициальным проектом и не связан с разработчиками Navidrome, rclone, Caddy или FFmpeg.

---

## Возможности

- Автоматическая установка Navidrome
- Подключение музыкальной библиотеки через rclone
- Поддержка Mail.ru Cloud (WebDAV)
- Автоматическая настройка systemd
- Автоматическое создание swap
- Настройка FUSE
- Ротация логов rclone
- Автоматические резервные копии базы Navidrome
- HTTPS через Caddy
- Поддержка DuckDNS
- Настройка Firewall (UFW)
- Полностью интерактивная установка

---

## Что устанавливается

- Navidrome
- rclone
- Caddy (при использовании HTTPS)
- ffmpeg
- fuse3
- UFW
- swap-файл
- systemd-сервисы

---

## Что потребуется

- Ubuntu 24.04 (или совместимая Debian-система)
- Root-доступ
- Музыкальная библиотека в Mail.ru Cloud
- Пароль приложения Mail.ru для WebDAV
- (необязательно) DuckDNS-домен для HTTPS

---

## Поддерживаемые облака

В текущей версии:

- ✅ Mail.ru Cloud (WebDAV)

Планируется:

- Google Drive
- Yandex Disk
- Mega

---

## Установка

```bash
chmod +x setup.sh
sudo ./setup.sh
```

Скрипт задаст несколько вопросов:

- использовать HTTPS или HTTP;
- доменное имя;
- использовать DuckDNS или нет;
- логин Mail.ru;
- пароль приложения WebDAV;
- папку с музыкой;
- размер кеша rclone;
- период сканирования библиотеки.

После этого установка полностью автоматическая.

---

## Что будет настроено

```
Интернет
      │
      ▼
  Caddy (HTTPS)
      │
      ▼
 Navidrome
      │
      ▼
   rclone
      │
      ▼
 Mail.ru Cloud
```

Музыка не копируется на VPS.

Файлы читаются напрямую из облака.

---

## Возможности HTTPS

При использовании собственного домена автоматически настраиваются:

- Let's Encrypt
- Caddy
- автоматическое продление сертификатов
- обратный прокси

При использовании DuckDNS дополнительно автоматически обновляется IP сервера каждые 5 минут.

---

## Что не делает скрипт

- не изменяет музыкальную библиотеку;
- не загружает музыку на VPS;
- не требует локального хранения музыки;
- не использует Docker.

---

## Производительность

Скрипт рассчитан на большие музыкальные библиотеки.

Проверялось на библиотеке более **27 000 треков**.

Первое сканирование Navidrome может занимать продолжительное время в зависимости от скорости облачного хранилища.

---

## Структура каталогов

```
/mnt/music                 библиотека
/var/cache/rclone          кеш rclone
/var/lib/navidrome         база Navidrome
/opt/navidrome             программа
/var/log/rclone.log        лог rclone
```

---

## Резервные копии

Каждый день автоматически создаётся резервная копия базы Navidrome.

Хранятся последние 14 дней.

---

## Безопасность

Пароль облачного хранилища не сохраняется в открытом виде.

Для rclone используется команда:

```
rclone obscure
```

HTTPS использует сертификаты Let's Encrypt.

---

## Лицензия

MIT License

## Credits / Благодарности

This project would not be possible without these amazing open-source projects:

Этот проект был бы невозможен без следующих проектов с открытым исходным кодом:

- Navidrome — https://github.com/navidrome/navidrome
- rclone — https://github.com/rclone/rclone
- Caddy — https://github.com/caddyserver/caddy
- FFmpeg — https://ffmpeg.org/

Special thanks to all developers and contributors of these projects.

Особая благодарность всем разработчикам и участникам этих проектов.
