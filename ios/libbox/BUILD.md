# Инструкция по сборке libbox для iOS

## Требования

1. **Go** (версия 1.21+):
```bash
# macOS
brew install go
```

2. **gomobile**:
```bash
go install golang.org/x/mobile/cmd/gomobile@latest
gomobile init
```

3. **Xcode** с Command Line Tools:
```bash
xcode-select --install
```

## Сборка

### Вариант 1: Сборка из исходников sing-box (рекомендуется)

1. Клонируйте репозиторий sing-box:
```bash
cd /tmp
git clone https://github.com/SagerNet/sing-box.git
cd sing-box
```

2. Соберите framework для iOS:
```bash
cd experimental/libbox
gomobile bind -target ios -o libbox.framework github.com/SagerNet/sing-box/experimental/libbox
```

3. Скопируйте framework в проект:
```bash
cp -R libbox.framework /Users/qusadprod/gitHub/sing_box/ios/Frameworks/
```

### Вариант 2: Сборка из локальных исходников

Если у вас уже есть исходники в `android/libbox/`:

1. Убедитесь, что исходники libbox находятся в правильном месте:
```bash
# Исходники должны быть в Go модуле
# Можно использовать исходники из android/libbox, но нужно настроить Go модуль
```

2. Соберите framework:
```bash
cd /path/to/sing-box/experimental/libbox
gomobile bind -target ios -o libbox.framework github.com/SagerNet/sing-box/experimental/libbox
```

### Вариант 3: Использование готового framework

Если у вас есть готовый framework из sing-box-for-apple:
```bash
# Скопируйте framework из репозитория sing-box-for-apple
cp -R /path/to/sing-box-for-apple/Libbox.framework ios/Frameworks/
```

## Интеграция в проект

1. Добавьте framework в Xcode:
   - Откройте проект в Xcode
   - Перетащите `libbox.framework` в проект
   - Убедитесь, что framework добавлен в "Frameworks, Libraries, and Embedded Content"

2. Обновите `podspec` (если используется CocoaPods):
```ruby
s.vendored_frameworks = 'Frameworks/libbox.framework'
```

3. Или добавьте вручную в Build Settings:
   - Framework Search Paths: `$(SRCROOT)/Frameworks`
   - Other Linker Flags: `-framework libbox`

## Использование

После сборки framework будет доступен как `Libbox` в Swift коде:

```swift
import Libbox

let service = LibboxNewService(config, platformInterface)
```

## Примечания

- Framework должен быть универсальным (arm64 + x86_64 для симулятора)
- Для реального устройства нужен arm64
- Для симулятора нужен x86_64 (Intel) или arm64 (Apple Silicon)

## Проверка framework

```bash
# Проверить архитектуры
lipo -info Frameworks/libbox.framework/libbox

# Должно показать что-то вроде:
# Architectures in the fat file: libbox are: arm64 x86_64
```

