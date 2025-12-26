# Скомпилированные библиотеки libbox

## Файлы

- `libbox.aar` (88MB) - для Android API 23+ (рекомендуется)
- `libbox-legacy.aar` (69MB) - для Android API 21-22 (legacy поддержка)

## Компиляция

Библиотеки скомпилированы из исходников в `android/libbox/` с помощью:
```bash
cd /tmp/sing-box-source
go run ./cmd/internal/build_libbox -target android
```

## Использование

В `android/build.gradle` добавлено:
```gradle
implementation files('libs/libbox.aar')
```

Для поддержки старых версий Android (API 21-22) можно также добавить:
```gradle
implementation files('libs/libbox-legacy.aar')
```

## Перекомпиляция

Если нужно перекомпилировать библиотеки:

1. Убедитесь, что установлены:
   - Go 1.24+
   - Java 17, 21 или 23
   - Android NDK
   - gomobile от sagernet: `go install github.com/sagernet/gomobile/cmd/gomobile@v0.1.10`

2. Запустите:
```bash
cd /tmp/sing-box-source
JAVA_HOME=/path/to/java17 go run ./cmd/internal/build_libbox -target android
```

3. Скопируйте файлы:
```bash
cp /tmp/sing-box-source/libbox*.aar android/libs/
```

## Дата компиляции

- libbox.aar: 25 декабря 2024
- libbox-legacy.aar: 25 декабря 2024

