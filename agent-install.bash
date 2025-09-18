#!/bin/bash

# Запрашиваем у пользователя clientId и clientSecret
read -p "Введите clientId: " CLIENT_ID
read -p "Введите clientSecret: " CLIENT_SECRET

# Проверяем, что clientId и clientSecret не пустые
if [ -z "$CLIENT_ID" ] || [ -z "$CLIENT_SECRET" ]; then
    echo "Ошибка: clientId и clientSecret не могут быть пустыми."
    exit 1
fi

# Функция для проверки и установки curl
install_curl() {
    if ! command -v curl &> /dev/null; then
        echo "curl не найден, пытаемся установить..."
        sudo apt-get update && sudo apt-get install -y curl
        if ! command -v curl &> /dev/null; then
            echo "Не удалось установить curl. Пожалуйста, установите его вручную."
            exit 1
        fi
    fi
}

# Функция для проверки и установки tar
install_tar() {
    if ! command -v tar &> /dev/null; then
        echo "tar не найден, пытаемся установить..."
        sudo apt-get update && sudo apt-get install -y tar
        if ! command -v tar &> /dev/null; then
            echo "Не удалось установить tar. Пожалуйста, установите его вручную."
            exit 1
        fi
    fi
}

# Функция для проверки и установки jq
install_jq() {
    if ! command -v jq &> /dev/null; then
        echo "jq не найден, пытаемся установить..."
        sudo apt-get update && sudo apt-get install -y jq
        if ! command -v jq &> /dev/null; then
            echo "Не удалось установить jq. Пожалуйста, установите его вручную."
            exit 1
        fi
    fi
}

# Проверяем и устанавливаем curl, tar, jq и host
install_curl
install_tar
install_jq

# URL XML-файла
URL="https://storage.projectlan.ru/clubagent/appcast.xml"

# Папка для разархивирования
DIST_DIR="dist"

# Извлекаем значение атрибута url из тега enclosure и сохраняем в переменную
ENCLOSURE_URL=$(curl -s "$URL" | grep -oP '<enclosure[^>]+url="\K[^"]+')

# Проверяем, удалось ли извлечь URL
if [ -n "$ENCLOSURE_URL" ]; then
    echo "Извлеченный URL: $ENCLOSURE_URL"
else
    echo "Не удалось извлечь URL"
    exit 1
fi

# Извлекаем имя файла из URL
FILENAME=$(basename "$ENCLOSURE_URL")

# Скачиваем файл по извлеченному URL
echo "Скачиваем файл: $FILENAME"
curl -O "$ENCLOSURE_URL"

# Проверяем, успешно ли скачан файл
if [ -f "$FILENAME" ]; then
    echo "Файл успешно скачан: $FILENAME"
else
    echo "Не удалось скачать файл"
    exit 1
fi

# Создаем папку dist, если она не существует
mkdir -p "$DIST_DIR"

# Разархивируем tar.gz файл в папку dist
echo "Разархивируем файл: $FILENAME в папку $DIST_DIR"
tar -xzf "$FILENAME" -C "$DIST_DIR"

# Проверяем, успешно ли разархивирован файл
if [ $? -eq 0 ]; then
    echo "Файл успешно разархивирован в $DIST_DIR"
else
    echo "Не удалось разархивировать файл"
    exit 1
fi

# Переименовываем appsettings.example.json в appsettings.json в папке dist
echo "Переименовываем appsettings.example.json в appsettings.json..."
if [ -f "$DIST_DIR/appsettings.example.json" ]; then
    mv "$DIST_DIR/appsettings.example.json" "$DIST_DIR/appsettings.json"
    if [ -f "$DIST_DIR/appsettings.json" ]; then
        echo "Файл успешно переименован в appsettings.json"
    else
        echo "Не удалось переименовать файл appsettings.example.json"
        exit 1
    fi
else
    echo "Файл appsettings.example.json не найден в $DIST_DIR"
    exit 1
fi

# Заменяем значения в appsettings.json
echo "Обновляем значения в appsettings.json..."
jq --arg client_id "$CLIENT_ID" \
   --arg client_secret "$CLIENT_SECRET" \
   '.PlConnectManagerUrl = "https://manager.projectlan.ru/" |
    .PlUpdateUrl = "https://storage.projectlan.ru/clubagent/appcast.xml" |
    .ClientInfo.ClientId = $client_id |
    .ClientInfo.ClientSecret = $client_secret' \
   "$DIST_DIR/appsettings.json" > "$DIST_DIR/appsettings.json.tmp" && \
mv "$DIST_DIR/appsettings.json.tmp" "$DIST_DIR/appsettings.json"

# Проверяем, успешно ли обновлен файл
if [ $? -eq 0 ]; then
    echo "Файл appsettings.json успешно обновлен"
else
    echo "Не удалось обновить appsettings.json"
    exit 1
fi

# Создаем пользователя pl-agent, если он не существует
if ! id "pl-agent" &> /dev/null; then
    echo "Создаем пользователя pl-agent..."
    sudo useradd -r -s /bin/false pl-agent
    if [ $? -eq 0 ]; then
        echo "Пользователь pl-agent успешно создан"
    else
        echo "Не удалось создать пользователя pl-agent"
        exit 1
    fi
else
    echo "Пользователь pl-agent уже существует"
fi

# Создаем директории, если они не существуют
echo "Создаем директории, если они еще не существуют..."
sudo mkdir -p /usr/pl/agent
sudo mkdir -p /usr/share/pl/connect-agent/DB
sudo mkdir -p /usr/share/pl/connect-agent/log

# Копируем файлы из папки dist в /usr/pl/agent
echo "Копируем файлы из $DIST_DIR в /usr/pl/agent..."
sudo cp -r "$DIST_DIR"/* /usr/pl/agent/

# Проверяем, успешно ли скопированы файлы
if [ $? -eq 0 ]; then
    echo "Файлы успешно скопированы в /usr/pl/agent"
else
    echo "Не удалось скопировать файлы"
    exit 1
fi

# Очищаем скачанный файл и папку dist
echo "Очищаем скачанный файл $FILENAME и папку $DIST_DIR..."
rm -f "$FILENAME"
rm -rf "$DIST_DIR"

# Проверяем, успешно ли удалены файлы
if [ ! -f "$FILENAME" ] && [ ! -d "$DIST_DIR" ]; then
    echo "Скачанный файл и папка dist успешно удалены"
else
    echo "Не удалось удалить скачанный файл или папку dist"
    exit 1
fi

# Назначаем права пользователю pl-agent на директории с chmod 774
echo "Назначаем права 774 пользователю pl-agent..."
sudo chown -R pl-agent:pl-agent /usr/pl/agent
sudo chown -R pl-agent:pl-agent /usr/share/pl/connect-agent
sudo chmod -R 774 /usr/pl/agent
sudo chmod -R 774 /usr/share/pl/connect-agent

# Проверяем, успешно ли назначены права
if [ $? -eq 0 ]; then
    echo "Права 774 успешно назначены пользователю pl-agent"
else
    echo "Не удалось назначить права"
    exit 1
fi

# Создаем systemd unit файл
echo "Создаем systemd unit файл для pl-agent..."
sudo tee /etc/systemd/system/pl-agent.service > /dev/null <<EOF
[Unit]
Description=PL Connect Agent

[Service]
User=pl-agent
Group=pl-agent
WorkingDirectory=/usr/pl/agent
ExecStart=/usr/pl/agent/PL.ConnectAgent.Web
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Проверяем, успешно ли создан unit файл
if [ -f "/etc/systemd/system/pl-agent.service" ]; then
    echo "Systemd unit файл успешно создан"
else
    echo "Не удалось создать systemd unit файл"
    exit 1
fi

# Перезагружаем systemd daemon
echo "Перезагружаем systemd daemon..."
sudo systemctl daemon-reload

# Включаем и запускаем сервис
echo "Включаем и запускаем сервис pl-agent..."
sudo systemctl enable pl-agent.service
sudo systemctl start pl-agent.service

# Проверяем статус сервиса
if sudo systemctl is-active --quiet pl-agent.service; then
    echo "Сервис pl-agent успешно запущен"
else
    echo "Не удалось запустить сервис pl-agent"
    sudo systemctl status pl-agent.service
    exit 1
fi

# Выводим clientId и clientSecret для подтверждения
echo "clientId: $CLIENT_ID"
echo "clientSecret: $CLIENT_SECRET"
