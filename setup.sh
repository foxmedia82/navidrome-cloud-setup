#!/bin/bash
set -e

echo "=================================================="
echo " Установка музыкального сервера (Navidrome + облако)"
echo "=================================================="
echo

# ---------- СБОР ДАННЫХ ----------

read -p "Домен для HTTPS-доступа (например music.duckdns.org), Enter — пропустить и использовать HTTP по IP:4533: " DOMAIN

USE_HTTPS=0
USE_DUCKDNS=0
if [ -n "$DOMAIN" ]; then
    USE_HTTPS=1
    read -p "Это домен на DuckDNS? (y/n): " IS_DUCKDNS
    if [ "$IS_DUCKDNS" = "y" ]; then
        USE_DUCKDNS=1
        DUCKDNS_SUBDOMAIN=$(echo "$DOMAIN" | cut -d'.' -f1)
        read -p "DuckDNS токен: " DUCKDNS_TOKEN
    fi
fi

echo
echo "--- Облачное хранилище ---"
echo "  1) Mail.ru Cloud"
read -p "Выберите провайдер [1]: " CLOUD_CHOICE
CLOUD_CHOICE=${CLOUD_CHOICE:-1}

case "$CLOUD_CHOICE" in
    1)
        CLOUD_TYPE="mailru"
        read -p "Email от Mail.ru: " CLOUD_USER
        read -s -p "Пароль приложения (созданный для WebDAV в настройках Mail.ru): " CLOUD_PASS
        echo
        read -p "Папка в облаке с музыкой (например Music Backup): " CLOUD_FOLDER
        ;;
    *)
        echo "Этот провайдер пока не поддерживается."
        exit 1
        ;;
esac

read -p "Максимальный размер кэша rclone в ГБ [1]: " CACHE_SIZE_GB
CACHE_SIZE_GB=${CACHE_SIZE_GB:-1}

# Время сброса кэша каталогов rclone (UTC)
read -p "Во сколько сбрасывать кэш списка файлов rclone (часы:минуты UTC) [05:00]: " CACHE_REFRESH_TIME
CACHE_REFRESH_TIME=${CACHE_REFRESH_TIME:-05:00}
CACHE_REFRESH_HOUR=$(echo "$CACHE_REFRESH_TIME" | cut -d: -f1 | sed 's/^0*//')
CACHE_REFRESH_MIN=$(echo "$CACHE_REFRESH_TIME" | cut -d: -f2 | sed 's/^0*//')
CACHE_REFRESH_HOUR=${CACHE_REFRESH_HOUR:-0}
CACHE_REFRESH_MIN=${CACHE_REFRESH_MIN:-0}

# Время ежедневного сканирования библиотеки Navidrome (UTC) — ставим позже сброса кэша,
# чтобы Navidrome гарантированно видел уже обновлённый список файлов
read -p "Во сколько сканировать библиотеку Navidrome (часы:минуты UTC) [05:30]: " SCAN_TIME
SCAN_TIME=${SCAN_TIME:-05:30}
SCAN_HOUR=$(echo "$SCAN_TIME" | cut -d: -f1 | sed 's/^0*//')
SCAN_MIN=$(echo "$SCAN_TIME" | cut -d: -f2 | sed 's/^0*//')
SCAN_HOUR=${SCAN_HOUR:-0}
SCAN_MIN=${SCAN_MIN:-0}
SCAN_SCHEDULE_CRON="$SCAN_MIN $SCAN_HOUR * * *"

echo
echo "=================== ПРОВЕРЬТЕ ДАННЫЕ ==================="
echo "Домен:               ${DOMAIN:-не используется (HTTP по IP:4533)}"
echo "DuckDNS:              $([ "$USE_DUCKDNS" = "1" ] && echo да || echo нет)"
echo "Облако:               $CLOUD_TYPE"
echo "Логин:                $CLOUD_USER"
echo "Папка в облаке:       $CLOUD_FOLDER"
echo "Кэш rclone:           ${CACHE_SIZE_GB}G"
echo "Сброс кэша файлов:    ежедневно в $CACHE_REFRESH_TIME UTC"
echo "Скан библиотеки:      ежедневно в $SCAN_TIME UTC"
echo "==========================================================="
read -p "Продолжить установку? (y/n): " CONFIRM
[ "$CONFIRM" = "y" ] || { echo "Отменено."; exit 1; }

# ---------- УСТАНОВКА ----------

echo ">>> Обновление системы и пакеты"
apt update && apt upgrade -y
apt install -y curl unzip fuse3 ufw ffmpeg

echo ">>> Swap-файл (идемпотентно)"
if [ ! -f /swapfile ]; then
    fallocate -l 1G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi
grep -qxF "vm.swappiness=10" /etc/sysctl.conf || echo "vm.swappiness=10" >> /etc/sysctl.conf
sysctl -p

echo ">>> Установка rclone"
curl https://rclone.org/install.sh | bash || true
rclone version

echo ">>> user_allow_other для FUSE"
grep -qxF 'user_allow_other' /etc/fuse.conf || echo 'user_allow_other' >> /etc/fuse.conf

echo ">>> Подключение к облаку ($CLOUD_TYPE)"
rclone config delete cloudmusic 2>/dev/null || true
OBSCURED_PASS=$(rclone obscure "$CLOUD_PASS")

case "$CLOUD_TYPE" in
    mailru)
        rclone config create cloudmusic webdav \
            url https://webdav.cloud.mail.ru \
            vendor other \
            user "$CLOUD_USER" \
            pass "$OBSCURED_PASS"
        ;;
esac

rclone lsd cloudmusic: || {
    echo "ОШИБКА: не удалось подключиться к облаку, проверьте логин/пароль/сеть"
    exit 1
}

echo ">>> Точка монтирования"
mkdir -p /mnt/music
mkdir -p /var/cache/rclone

if command -v fusermount3 >/dev/null 2>&1; then
    FUSERMOUNT_BIN=$(command -v fusermount3)
else
    FUSERMOUNT_BIN=$(command -v fusermount)
fi

cat > /etc/systemd/system/rclone-music.service << EOF
[Unit]
Description=rclone mount music from cloud
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStartPre=/bin/sleep 5
ExecStart=/usr/bin/rclone mount "cloudmusic:$CLOUD_FOLDER" /mnt/music \\
  --config=/root/.config/rclone/rclone.conf \\
  --allow-other \\
  --vfs-cache-mode full \\
  --vfs-cache-max-size ${CACHE_SIZE_GB}G \\
  --vfs-cache-max-age 24h \\
  --cache-dir /var/cache/rclone \\
  --dir-cache-time 72h \\
  --poll-interval 0 \\
  --buffer-size 64M \\
  --transfers 2 \\
  --checkers 4 \\
  --timeout 2m \\
  --contimeout 15s \\
  --log-file=/var/log/rclone.log \\
  --log-level INFO \\
  --umask 002
ExecStop=$FUSERMOUNT_BIN -u /mnt/music
Restart=on-failure
RestartSec=10
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now rclone-music.service

timeout 30 bash -c '
until mountpoint -q /mnt/music
do
    sleep 1
done
' || echo "ВНИМАНИЕ: mount не подтвердился за 30 секунд, проверьте: systemctl status rclone-music"

systemctl is-active --quiet rclone-music.service && echo "rclone-music: активен"
ls /mnt/music | head || true

echo ">>> Ротация лога rclone (лог именно этого приложения)"
cat > /etc/logrotate.d/rclone << 'EOF'
/var/log/rclone.log {
    weekly
    rotate 4
    size 50M
    compress
    missingok
    notifempty
    copytruncate
    create 0644 root root
}
EOF

echo ">>> Автоматический сброс кэша списка файлов rclone (ежедневно)"
cat > /opt/refresh-music-cache.sh << 'EOF'
#!/bin/bash
kill -SIGHUP $(pgrep -f "rclone mount cloudmusic") 2>/dev/null
EOF
chmod 700 /opt/refresh-music-cache.sh

cat > /etc/cron.d/refresh-music-cache << EOF
$CACHE_REFRESH_MIN $CACHE_REFRESH_HOUR * * * root /opt/refresh-music-cache.sh >/dev/null 2>&1
EOF

echo ">>> Установка Navidrome (с проверками и ретраями)"
mkdir -p /opt/navidrome /var/lib/navidrome
cd /opt/navidrome

if [ -x /opt/navidrome/navidrome ] && /opt/navidrome/navidrome --version >/dev/null 2>&1; then
    echo "Navidrome уже установлен: $(/opt/navidrome/navidrome --version)"
else
    rm -f /opt/navidrome/navidrome.tar.gz /opt/navidrome/navidrome /opt/navidrome/LICENSE /opt/navidrome/README.md

    NAVIDROME_VERSION=""
    for i in 1 2 3; do
        NAVIDROME_VERSION=$(curl -fsS --max-time 15 https://api.github.com/repos/navidrome/navidrome/releases/latest \
            | grep -oP '"tag_name": "\K(v[^"]+)') && [ -n "$NAVIDROME_VERSION" ] && break
        echo "Не удалось получить версию Navidrome, попытка $i/3..."
        sleep 5
    done

    if [ -z "$NAVIDROME_VERSION" ]; then
        echo "ОШИБКА: не удалось получить версию Navidrome с GitHub API"
        exit 1
    fi
    NAVIDROME_VERSION_NUM=${NAVIDROME_VERSION#v}
    echo "Версия Navidrome: $NAVIDROME_VERSION"

    DOWNLOAD_OK=0
    for i in 1 2 3; do
        if curl -fsSL --max-time 120 -o navidrome.tar.gz \
            "https://github.com/navidrome/navidrome/releases/download/${NAVIDROME_VERSION}/navidrome_${NAVIDROME_VERSION_NUM}_linux_amd64.tar.gz"; then
            DOWNLOAD_OK=1
            break
        fi
        echo "Скачивание не удалось, попытка $i/3..."
        rm -f navidrome.tar.gz
        sleep 5
    done

    if [ "$DOWNLOAD_OK" != "1" ]; then
        echo "ОШИБКА: не удалось скачать Navidrome после 3 попыток"
        exit 1
    fi

    if ! gzip -t navidrome.tar.gz 2>/dev/null; then
        echo "ОШИБКА: скачанный архив navidrome.tar.gz повреждён"
        exit 1
    fi

    tar -xvzf navidrome.tar.gz
    rm navidrome.tar.gz

    if ! /opt/navidrome/navidrome --version >/dev/null 2>&1; then
        echo "ОШИБКА: бинарник Navidrome не запускается после распаковки"
        exit 1
    fi
    echo "Navidrome установлен: $(/opt/navidrome/navidrome --version)"
fi

cat > /opt/navidrome/navidrome.toml << EOF
MusicFolder = "/mnt/music"
DataFolder = "/var/lib/navidrome"
Port = 4533
Address = "0.0.0.0"
ScanSchedule = "$SCAN_SCHEDULE_CRON"
LogLevel = "INFO"
EnableInsightsCollector = false
EOF

cat > /etc/systemd/system/navidrome.service << 'EOF'
[Unit]
Description=Navidrome Music Server
After=rclone-music.service network-online.target
Requires=rclone-music.service

[Service]
Type=simple
WorkingDirectory=/opt/navidrome
ExecStart=/opt/navidrome/navidrome --configfile /opt/navidrome/navidrome.toml
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now navidrome
sleep 3
curl -fs http://127.0.0.1:4533 >/dev/null && echo "Navidrome отвечает: OK" || echo "ВНИМАНИЕ: проверьте journalctl -u navidrome -n 30"

echo ">>> Бэкап базы Navidrome"
mkdir -p /root/navidrome-backups
cat > /etc/cron.d/navidrome-backup << 'EOF'
0 4 * * * root tar -czf /root/navidrome-backups/navidrome-$(date +\%Y\%m\%d).tar.gz -C /var/lib/navidrome . && find /root/navidrome-backups -type f -mtime +14 -delete
EOF

# ---------- HTTPS (по желанию) ----------

if [ "$USE_HTTPS" = "1" ]; then

    if [ "$USE_DUCKDNS" = "1" ]; then
        echo ">>> DuckDNS"
        mkdir -p /opt/duckdns
        cat > /opt/duckdns/duck.sh << EOF
#!/bin/bash
curl -fsS "https://www.duckdns.org/update?domains=${DUCKDNS_SUBDOMAIN}&token=${DUCKDNS_TOKEN}&ip=" \\
    | tee /var/log/duckdns.log
EOF
        chmod 700 /opt/duckdns/duck.sh
        /opt/duckdns/duck.sh || echo "ВНИМАНИЕ: DuckDNS не ответил, проверьте позже: /opt/duckdns/duck.sh"

        cat > /etc/cron.d/duckdns << 'EOF'
*/5 * * * * root /opt/duckdns/duck.sh >/dev/null 2>&1
EOF
    fi

    echo ">>> Установка Caddy"
    apt install -y debian-keyring debian-archive-keyring apt-transport-https
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
    apt update
    apt install -y caddy

    cat > /etc/caddy/Caddyfile << EOF
$DOMAIN {
    reverse_proxy localhost:4533
}
EOF
    caddy validate --config /etc/caddy/Caddyfile
    systemctl restart caddy
    sleep 5

    echo ">>> Настройка firewall (безопасно для серверов с уже работающими сервисами)"
    if ufw status | grep -q "Status: active"; then
        echo "UFW уже включён. Добавляю только необходимые правила..."
    else
        echo "UFW ещё не включён. Включаю с базовыми правилами..."
        ufw --force enable
    fi
    ufw allow 22/tcp
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw delete allow 4533/tcp || true
    ufw status verbose

    echo ">>> Проверка HTTPS"
    for i in 1 2 3 4 5 6; do
        if curl -fsI "https://$DOMAIN" >/dev/null 2>&1; then
            echo "HTTPS работает: https://$DOMAIN"
            break
        fi
        sleep 10
    done

else
    echo ">>> Настройка firewall (безопасно для серверов с уже работающими сервисами)"
    if ufw status | grep -q "Status: active"; then
        echo "UFW уже включён. Добавляю только необходимые правила..."
    else
        echo "UFW ещё не включён. Включаю с базовыми правилами..."
        ufw --force enable
    fi
    ufw allow 22/tcp
    ufw allow 4533/tcp
    ufw status verbose
    echo ">>> Доступ по HTTP: http://$(curl -s ifconfig.me):4533"
fi

echo
echo "=== ГОТОВО ==="
echo "Откройте адрес выше в браузере для создания администратора Navidrome"
