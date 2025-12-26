#!/bin/bash
set -e

echo "=== 🔨 СБОРКА LIBBOX ДЛЯ iOS ==="
echo ""

# Проверка Go
if ! command -v go >/dev/null 2>&1; then
    echo "❌ Go не установлен. Установите через: brew install go"
    exit 1
fi

echo "✅ Go установлен: $(go version)"
echo ""

# Проверка gomobile
GOMOBILE=""
if command -v gomobile >/dev/null 2>&1; then
    GOMOBILE="gomobile"
elif [ -f ~/go/bin/gomobile ]; then
    GOMOBILE="~/go/bin/gomobile"
else
    echo "📦 Установка gomobile..."
    go install golang.org/x/mobile/cmd/gomobile@latest
    GOMOBILE="~/go/bin/gomobile"
fi

echo "✅ gomobile: $GOMOBILE"
echo ""

# Инициализация gomobile
echo "🔧 Инициализация gomobile..."
$GOMOBILE init || true
echo ""

# Проверка исходников
if [ ! -d "/tmp/sing-box" ]; then
    echo "📥 Клонирование sing-box..."
    cd /tmp
    git clone --depth 1 https://github.com/SagerNet/sing-box.git || true
fi

if [ ! -d "/tmp/sing-box/experimental/libbox" ]; then
    echo "❌ Исходники libbox не найдены"
    exit 1
fi

echo "✅ Исходники найдены"
echo ""

# Сборка
echo "🔨 Сборка libbox.framework для iOS..."
cd /tmp/sing-box/experimental/libbox

# Очистка предыдущей сборки
rm -rf libbox.framework

# Сборка для iOS
$GOMOBILE bind -target ios -o libbox.framework github.com/SagerNet/sing-box/experimental/libbox

if [ ! -d "libbox.framework" ]; then
    echo "❌ Сборка не удалась"
    exit 1
fi

echo "✅ Framework собран"
echo ""

# Копирование в проект
PROJECT_DIR="/Users/qusadprod/gitHub/sing_box"
FRAMEWORK_DIR="$PROJECT_DIR/ios/Frameworks"

mkdir -p "$FRAMEWORK_DIR"
rm -rf "$FRAMEWORK_DIR/libbox.framework"
cp -R libbox.framework "$FRAMEWORK_DIR/"

echo "✅ Framework скопирован в $FRAMEWORK_DIR"
echo ""

# Проверка архитектур
echo "📊 Архитектуры в framework:"
lipo -info "$FRAMEWORK_DIR/libbox.framework/libbox" 2>/dev/null || echo "   (не удалось проверить)"

echo ""
echo "=== ✅ СБОРКА ЗАВЕРШЕНА ==="
echo ""
echo "Framework находится в: ios/Frameworks/libbox.framework"
