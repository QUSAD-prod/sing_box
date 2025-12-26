# libbox - библиотека для работы с sing-box

## Описание

Эта папка содержит исходники библиотеки `libbox` из репозитория [sing-box](https://github.com/SagerNet/sing-box).

## Источник

Скопировано из: `/tmp/sing-box-source/experimental/libbox`

Оригинальный репозиторий: https://github.com/SagerNet/sing-box

## Что это?

`libbox` - это Go библиотека, которая предоставляет API для работы с sing-box из Android/Kotlin через JNI (Java Native Interface).

## Компиляция

Для компиляции в Android библиотеку (.aar) необходимо:

1. Установить Go и gomobile:
```bash
go install golang.org/x/mobile/cmd/gomobile@latest
gomobile init
```

2. Скомпилировать библиотеку:
```bash
cd android/libbox
gomobile bind -target android -o libbox.aar github.com/SagerNet/sing-box/experimental/libbox
```

3. Добавить в `android/build.gradle`:
```gradle
dependencies {
    implementation files('libs/libbox.aar')
}
```

## Структура

- `command.go` - команды для управления sing-box
- `command_client.go` - клиент для выполнения команд
- `config.go` - работа с конфигурацией
- `dns.go` - DNS функциональность
- `log.go` - логирование
- `memory.go` - управление памятью
- `monitor.go` - мониторинг
- `pprof.go` - профилирование
- И другие файлы...

## Использование

После компиляции библиотека будет доступна как `io.nekohasekai.libbox.*` в Kotlin коде.

## Примечание

Эти исходники нужно скомпилировать с помощью `gomobile` для получения Android библиотеки (.aar файл).

