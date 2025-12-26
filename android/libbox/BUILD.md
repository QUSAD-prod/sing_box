# Инструкция по сборке libbox для Android

## Вариант 1: Использовать готовую библиотеку из sing-box-for-android

Если у вас есть доступ к скомпилированной библиотеке из sing-box-for-android:

1. Скопируйте файл `libbox.aar` в `android/libs/`
2. Добавьте в `android/build.gradle`:
```gradle
dependencies {
    implementation files('libs/libbox.aar')
}
```

## Вариант 2: Собрать библиотеку самостоятельно

### Требования

1. Установите Go (версия 1.21+):
```bash
# macOS
brew install go

# Linux
sudo apt-get install golang-go
```

2. Установите gomobile:
```bash
go install golang.org/x/mobile/cmd/gomobile@latest
gomobile init
```

3. Установите Android NDK (через Android Studio или отдельно)

### Сборка

1. Перейдите в директорию с исходниками sing-box:
```bash
cd /path/to/sing-box
```

2. Соберите библиотеку:
```bash
cd experimental/libbox
gomobile bind -target android -androidapi 21 -o libbox.aar github.com/SagerNet/sing-box/experimental/libbox
```

3. Скопируйте `libbox.aar` в `android/libs/` вашего проекта

4. Добавьте в `android/build.gradle`:
```gradle
dependencies {
    implementation files('libs/libbox.aar')
}
```

## Вариант 3: Использовать как локальный модуль (если есть модуль libbox)

Если в sing-box-for-android есть модуль libbox:

1. Скопируйте модуль libbox в `android/`
2. Добавьте в `android/settings.gradle`:
```gradle
include ':libbox'
project(':libbox').projectDir = new File('libbox')
```

3. Добавьте в `android/build.gradle`:
```gradle
dependencies {
    implementation project(':libbox')
}
```

## Текущее состояние

Исходники libbox скопированы в `android/libbox/`, но это Go код, который нужно скомпилировать.

Для использования в Android нужна скомпилированная библиотека (.aar файл).

## Рекомендация

Лучше всего использовать готовую библиотеку из sing-box-for-android или собрать её один раз и добавить в `android/libs/`.

