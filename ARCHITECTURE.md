# Архитектура пакета sing_box

## Обзор

Пакет `sing_box` представляет собой Flutter плагин для работы с VPN на основе sing-box. Пакет использует паттерн Singleton для доступа из любого места приложения и поддерживает платформо-независимый интерфейс для работы с нативными реализациями Android и iOS.

## Структура проекта

```
lib/
├── sing_box.dart                    # Главный класс API (Singleton)
├── sing_box_platform_interface.dart # Абстрактный платформенный интерфейс
├── sing_box_method_channel.dart     # Реализация через Method Channels
└── src/
    ├── models/                      # Модели данных
    │   ├── connection_status.dart
    │   ├── connection_stats.dart
    │   ├── ping_result.dart
    │   ├── speed_test_result.dart
    │   ├── settings.dart
    │   ├── server_config.dart
    │   └── models.dart
    └── observer/                    # Observer для логирования
        ├── sing_box_observer.dart
        ├── talker_observer.dart
        └── observer.dart
```

## Архитектурные паттерны

### 1. Singleton Pattern
Класс `SingBox` реализует паттерн Singleton, обеспечивая единственный экземпляр на все приложение:
- Приватный конструктор `SingBox._()`
- Статический геттер `instance` для получения экземпляра
- Инициализация через метод `initialize()`

### 2. Platform Interface Pattern
Используется `plugin_platform_interface` для создания платформо-независимого API:
- `SingBoxPlatform` - абстрактный базовый класс
- `MethodChannelSingBox` - реализация через Method Channels
- Возможность создания собственных платформенных реализаций

### 3. Observer Pattern
Реализован паттерн Observer для логирования событий:
- `SingBoxObserver` - интерфейс для наблюдения
- `SingBoxNoOpObserver` - пустая реализация по умолчанию
- `SingBoxTalkerObserver` - интеграция с библиотекой Talker

## Основные классы

### SingBox

Главный класс для работы с VPN. Реализует паттерн Singleton.

#### Свойства

- `static SingBox get instance` - получить экземпляр (Singleton)
- `bool get isInitialized` - проверка инициализации плагина
- `SingBoxObserver get observer` - получить текущий observer

#### Методы инициализации

##### `Future<bool> initialize()`
Инициализирует плагин. Должен быть вызван до использования других методов, желательно до старта приложения.

**Возвращает:** `true` если инициализация успешна, `false` в противном случае.

##### `void setObserver(SingBoxObserver observer)`
Устанавливает observer для логирования событий. Поддерживает интеграцию с Talker через `SingBoxTalkerObserver`.

**Параметры:**
- `observer` - экземпляр observer для логирования

#### Методы подключения

##### `Future<bool> connect(String config)`
Подключается к VPN с указанной конфигурацией.

**Параметры:**
- `config` - JSON строка с конфигурацией сервера

**Возвращает:** `true` если подключение успешно, `false` в противном случае.

**События observer:**
- `onConnect(config)` - при начале подключения
- `info('Connected to VPN successfully')` - при успешном подключении
- `onConnectionError(error)` - при ошибке подключения

##### `Future<bool> disconnect()`
Отключается от VPN.

**Возвращает:** `true` если отключение успешно, `false` в противном случае.

**События observer:**
- `onDisconnect()` - при начале отключения
- `info('Disconnected from VPN successfully')` - при успешном отключении

##### `Future<bool> switchServer(String config)`
Сменяет текущий сервер. Останавливает текущее подключение, меняет конфигурацию и подключается к новому серверу.

**Параметры:**
- `config` - JSON строка с новой конфигурацией сервера

**Возвращает:** `true` если смена сервера успешна, `false` в противном случае.

#### Методы получения статуса и статистики

##### `Future<SingBoxConnectionStatus> getSingBoxConnectionStatus()`
Получает текущий статус подключения.

**Возвращает:** `SingBoxConnectionStatus` - текущий статус подключения.

**События observer:**
- `onStatusChanged(status.name)` - при получении статуса

##### `Future<SingBoxConnectionStats> getSingBoxConnectionStats()`
Получает текущую статистику подключения, включая скорость загрузки/отдачи, отправлено/получено байт, пинг, время подключения.

**Возвращает:** `SingBoxConnectionStats` - объект со статистикой.

**События observer:**
- `onSingBoxConnectionStatsChanged(stats)` - при получении статистики

##### `Stream<SingBoxConnectionStatus> watchSingBoxConnectionStatus()`
Подписывается на изменения статуса подключения в реальном времени.

**Возвращает:** `Stream<SingBoxConnectionStatus>` - поток обновлений статуса.

**События в Stream:**
- Обновления статуса при каждом изменении (disconnected, connecting, connected, disconnecting, disconnectedByUser, connectionLost, error)

##### `Stream<SingBoxConnectionStats> watchSingBoxConnectionStats()`
Подписывается на изменения статистики подключения в реальном времени. Включает скорость загрузки/отдачи, отправлено/получено байт, пинг, время подключения.

**Возвращает:** `Stream<SingBoxConnectionStats>` - поток обновлений статистики.

**События в Stream:**
- Постоянные обновления статистики подключения

#### Методы измерения скорости и пинга

##### `Future<SingBoxSpeedTestResult> testSpeed()`
Измеряет скорость подключения.

**Возвращает:** `SingBoxSpeedTestResult` - результат измерения скорости (downloadSpeed, uploadSpeed в байтах в секунду).

##### `Future<SingBoxPingResult> pingCurrentServer()`
Измеряет пинг до текущего сервера.

**Возвращает:** `SingBoxPingResult` - результат измерения пинга (ping в миллисекундах, success, errorMessage, address).

##### `Future<SingBoxPingResult> pingConfig(String config)`
Измеряет пинг до указанного конфига.

**Параметры:**
- `config` - JSON строка с конфигурацией сервера

**Возвращает:** `SingBoxPingResult` - результат измерения пинга.

#### Методы работы с исключениями (Bypass)

##### `Future<bool> addAppToBypass(String packageName)`
Добавляет приложение в список исключений (не будет использовать VPN).

**Параметры:**
- `packageName` - имя пакета приложения (Android) или bundle ID (iOS)

**Возвращает:** `true` если добавление успешно, `false` в противном случае.

##### `Future<bool> removeAppFromBypass(String packageName)`
Удаляет приложение из списка исключений.

**Параметры:**
- `packageName` - имя пакета приложения (Android) или bundle ID (iOS)

**Возвращает:** `true` если удаление успешно, `false` в противном случае.

##### `Future<List<String>> getBypassApps()`
Получает список приложений в исключениях.

**Возвращает:** `List<String>` - список имен пакетов приложений.

##### `Future<bool> addDomainToBypass(String domain)`
Добавляет домен/сайт в список исключений (не будет использовать VPN).

**Параметры:**
- `domain` - доменное имя или IP адрес

**Возвращает:** `true` если добавление успешно, `false` в противном случае.

##### `Future<bool> removeDomainFromBypass(String domain)`
Удаляет домен/сайт из списка исключений.

**Параметры:**
- `domain` - доменное имя или IP адрес

**Возвращает:** `true` если удаление успешно, `false` в противном случае.

##### `Future<List<String>> getBypassDomains()`
Получает список доменов/сайтов в исключениях.

**Возвращает:** `List<String>` - список доменов/сайтов.

#### Методы работы с настройками

##### `Future<bool> saveSingBoxSettings(SingBoxSettings settings)`
Сохраняет настройки плагина.

**Параметры:**
- `settings` - объект с настройками для сохранения

**Возвращает:** `true` если сохранение успешно, `false` в противном случае.

**События observer:**
- `info('Saving settings')` - при начале сохранения
- `info('SingBoxSettings saved successfully')` - при успешном сохранении

##### `Future<SingBoxSettings> loadSingBoxSettings()`
Загружает сохраненные настройки.

**Возвращает:** `SingBoxSettings` - объект с настройками.

##### `Future<SingBoxSettings> getSingBoxSettings()`
Получает текущие настройки.

**Возвращает:** `SingBoxSettings` - объект с текущими настройками.

##### `Future<bool> updateSetting(String key, dynamic value)`
Обновляет отдельный параметр настроек.

**Параметры:**
- `key` - ключ параметра (autoConnectOnStart, autoReconnectOnDisconnect, killSwitch)
- `value` - значение параметра

**Возвращает:** `true` если обновление успешно, `false` в противном случае.

**События observer:**
- `onSingBoxSettingsChanged(key, value)` - при изменении настройки
- `debug('Setting updated', {'key': key, 'value': value})` - при успешном обновлении

#### Методы работы с конфигурациями серверов

##### `Future<bool> addSingBoxServerConfig(SingBoxServerConfig config)`
Добавляет конфигурацию сервера.

**Параметры:**
- `config` - конфигурация сервера (SingBoxServerConfig)

**Возвращает:** `true` если добавление успешно, `false` в противном случае.

**События observer:**
- `onSingBoxServerConfigAdded(config.id, config.name)` - при добавлении конфигурации
- `info('Server config added successfully', {...})` - при успешном добавлении

##### `Future<bool> removeSingBoxServerConfig(String configId)`
Удаляет конфигурацию сервера.

**Параметры:**
- `configId` - идентификатор конфигурации

**Возвращает:** `true` если удаление успешно, `false` в противном случае.

**События observer:**
- `onSingBoxServerConfigRemoved(configId)` - при удалении конфигурации
- `info('Server config removed successfully', {'id': configId})` - при успешном удалении

##### `Future<bool> updateSingBoxServerConfig(SingBoxServerConfig config)`
Обновляет конфигурацию сервера.

**Параметры:**
- `config` - обновленная конфигурация сервера

**Возвращает:** `true` если обновление успешно, `false` в противном случае.

##### `Future<List<SingBoxServerConfig>> getSingBoxServerConfigs()`
Получает все конфигурации серверов.

**Возвращает:** `List<SingBoxServerConfig>` - список всех конфигураций.

##### `Future<SingBoxServerConfig?> getSingBoxServerConfig(String configId)`
Получает конфигурацию сервера по ID.

**Параметры:**
- `configId` - идентификатор конфигурации

**Возвращает:** `SingBoxServerConfig?` - конфигурация сервера или `null` если не найдена.

##### `Future<bool> setActiveSingBoxServerConfig(String configId)`
Устанавливает активную конфигурацию сервера.

**Параметры:**
- `configId` - идентификатор конфигурации

**Возвращает:** `true` если установка успешна, `false` в противном случае.

**События observer:**
- `onActiveSingBoxServerConfigChanged(configId)` - при смене активной конфигурации
- `info('Active server config changed', {'id': configId})` - при успешной смене

##### `Future<SingBoxServerConfig?> getActiveSingBoxServerConfig()`
Получает активную конфигурацию сервера.

**Возвращает:** `SingBoxServerConfig?` - активная конфигурация или `null` если не установлена.

#### Методы работы с заблокированными приложениями и доменами

##### `Future<bool> addBlockedApp(String packageName)`
Добавляет приложение в список заблокированных.

**Параметры:**
- `packageName` - имя пакета приложения (Android) или bundle ID (iOS)

**Возвращает:** `true` если добавление успешно, `false` в противном случае.

##### `Future<bool> removeBlockedApp(String packageName)`
Удаляет приложение из списка заблокированных.

**Параметры:**
- `packageName` - имя пакета приложения (Android) или bundle ID (iOS)

**Возвращает:** `true` если удаление успешно, `false` в противном случае.

##### `Future<List<String>> getBlockedApps()`
Получает список заблокированных приложений.

**Возвращает:** `List<String>` - список имен пакетов заблокированных приложений.

##### `Future<bool> addBlockedDomain(String domain)`
Добавляет домен/сайт в список заблокированных.

**Параметры:**
- `domain` - доменное имя или IP адрес

**Возвращает:** `true` если добавление успешно, `false` в противном случае.

##### `Future<bool> removeBlockedDomain(String domain)`
Удаляет домен/сайт из списка заблокированных.

**Параметры:**
- `domain` - доменное имя или IP адрес

**Возвращает:** `true` если удаление успешно, `false` в противном случае.

##### `Future<List<String>> getBlockedDomains()`
Получает список заблокированных доменов/сайтов.

**Возвращает:** `List<String>` - список заблокированных доменов/сайтов.

#### Методы работы с исключенными подсетями (Bypass Subnets)

##### `Future<bool> addSubnetToBypass(String subnet)`
Добавляет подсеть в список исключений (не будет использовать VPN).

**Параметры:**
- `subnet` - подсеть в формате CIDR (например: "192.168.1.0/24", "10.0.0.0/8")

**Возвращает:** `true` если добавление успешно, `false` в противном случае.

**События observer:**
- `info('Adding subnet to bypass', {'subnet': subnet})` - при начале добавления
- `debug('Subnet added to bypass successfully', {'subnet': subnet})` - при успешном добавлении

##### `Future<bool> removeSubnetFromBypass(String subnet)`
Удаляет подсеть из списка исключений.

**Параметры:**
- `subnet` - подсеть в формате CIDR

**Возвращает:** `true` если удаление успешно, `false` в противном случае.

**События observer:**
- `info('Removing subnet from bypass', {'subnet': subnet})` - при начале удаления
- `debug('Subnet removed from bypass successfully', {'subnet': subnet})` - при успешном удалении

##### `Future<List<String>> getBypassSubnets()`
Получает список подсетей в исключениях.

**Возвращает:** `List<String>` - список подсетей в формате CIDR.

#### Методы работы с DNS серверами

##### `Future<bool> addDnsServer(String dnsServer)`
Добавляет DNS сервер.

**Параметры:**
- `dnsServer` - IP адрес DNS сервера (например: "8.8.8.8", "1.1.1.1")

**Возвращает:** `true` если добавление успешно, `false` в противном случае.

**События observer:**
- `info('Adding DNS server', {'dnsServer': dnsServer})` - при начале добавления
- `debug('DNS server added successfully', {'dnsServer': dnsServer})` - при успешном добавлении

##### `Future<bool> removeDnsServer(String dnsServer)`
Удаляет DNS сервер.

**Параметры:**
- `dnsServer` - IP адрес DNS сервера

**Возвращает:** `true` если удаление успешно, `false` в противном случае.

**События observer:**
- `info('Removing DNS server', {'dnsServer': dnsServer})` - при начале удаления
- `debug('DNS server removed successfully', {'dnsServer': dnsServer})` - при успешном удалении

##### `Future<List<String>> getDnsServers()`
Получает список DNS серверов.

**Возвращает:** `List<String>` - список IP адресов DNS серверов.

##### `Future<bool> setDnsServers(List<String> dnsServers)`
Устанавливает DNS серверы (заменяет все существующие).

**Параметры:**
- `dnsServers` - список IP адресов DNS серверов

**Возвращает:** `true` если установка успешна, `false` в противном случае.

**События observer:**
- `info('Setting DNS servers', {'dnsServers': dnsServers})` - при начале установки
- `debug('DNS servers set successfully', {'count': dnsServers.length})` - при успешной установке

#### Вспомогательные методы

##### `Future<String?> getPlatformVersion()`
Получает версию платформы.

**Возвращает:** `String?` - версия платформы или `null`.

## Модели данных

### SingBoxConnectionStatus

Enum для статусов подключения VPN.

**Значения:**
- `disconnected` - не подключено
- `connecting` - подключение в процессе
- `connected` - подключено
- `disconnecting` - отключение в процессе
- `disconnectedByUser` - отключено пользователем
- `connectionLost` - потеря связи с сервером
- `error` - ошибка подключения

**Методы:**
- `String get name` - получить строковое представление статуса
- `static SingBoxConnectionStatus fromString(String value)` - создать из строки

### SingBoxConnectionStats

Статистика подключения.

**Поля:**
- `int downloadSpeed` - текущая скорость загрузки в байтах в секунду
- `int uploadSpeed` - текущая скорость отдачи в байтах в секунду
- `int bytesSent` - всего отправлено байт
- `int bytesReceived` - всего получено байт
- `int? ping` - текущий пинг в миллисекундах (может быть null)
- `int connectionDuration` - время подключения в миллисекундах с момента начала подключения

**Методы:**
- `factory SingBoxConnectionStats.fromMap(Map<dynamic, dynamic> map)` - создать из Map
- `Map<String, dynamic> toMap()` - преобразовать в Map

### SingBoxPingResult

Результат измерения пинга.

**Поля:**
- `int ping` - пинг в миллисекундах
- `bool success` - успешно ли выполнен пинг
- `String? errorMessage` - сообщение об ошибке, если пинг не удался
- `String? address` - адрес, до которого измерялся пинг

**Методы:**
- `factory SingBoxPingResult.fromMap(Map<dynamic, dynamic> map)` - создать из Map
- `Map<String, dynamic> toMap()` - преобразовать в Map

### SingBoxSpeedTestResult

Результат измерения скорости подключения.

**Поля:**
- `int downloadSpeed` - скорость загрузки в байтах в секунду
- `int uploadSpeed` - скорость отдачи в байтах в секунду
- `bool success` - успешно ли выполнен тест
- `String? errorMessage` - сообщение об ошибке, если тест не удался

**Методы:**
- `factory SingBoxSpeedTestResult.fromMap(Map<dynamic, dynamic> map)` - создать из Map
- `Map<String, dynamic> toMap()` - преобразовать в Map

### SingBoxSettings

Настройки плагина.

**Поля:**
- `bool autoConnectOnStart` - подключаться автоматически при старте приложения
- `bool autoReconnectOnDisconnect` - автоматически переподключаться при потере соединения
- `bool killSwitch` - блокировать весь интернет при отключении VPN
- `List<String> blockedApps` - список приложений, заблокированных для подключения через VPN
- `List<String> blockedDomains` - список сайтов/доменов, заблокированных для подключения через VPN
- `List<String> bypassSubnets` - список подсетей для исключения из VPN (формат CIDR, например: "192.168.1.0/24", "10.0.0.0/8")
  - По умолчанию: локальные сети (192.168.0.0/16, 10.0.0.0/8, 172.16.0.0/12, 127.0.0.0/8, 169.254.0.0/16)
- `List<String> dnsServers` - список DNS серверов (IP адреса, например: "8.8.8.8", "1.1.1.1")
  - По умолчанию: публичные DNS (8.8.8.8 - Google DNS, 1.1.1.1 - Cloudflare DNS)
- `String? activeSingBoxServerConfigId` - ID текущей активной конфигурации сервера
- `List<SingBoxServerConfig> serverConfigs` - список конфигураций серверов

**Методы:**
- `factory SingBoxSettings.fromMap(Map<dynamic, dynamic> map)` - создать из Map
- `Map<String, dynamic> toMap()` - преобразовать в Map
- `SingBoxSettings copyWith({...})` - создать копию с измененными полями

### SingBoxServerConfig

Конфигурация сервера с протоколом.

**Поля:**
- `String id` - уникальный идентификатор конфигурации
- `String name` - название конфигурации
- `String config` - JSON строка с конфигурацией сервера
- `String protocol` - протокол (например: vmess, vless, shadowsocks, trojan, etc.)
- `String server` - сервер (hostname или IP)
- `int port` - порт
- `bool enabled` - включена ли эта конфигурация

**Методы:**
- `factory SingBoxServerConfig.fromMap(Map<dynamic, dynamic> map)` - создать из Map
- `Map<String, dynamic> toMap()` - преобразовать в Map
- `SingBoxServerConfig copyWith({...})` - создать копию с измененными полями

## Observer Pattern

### SingBoxObserver

Интерфейс для наблюдения за событиями SingBox. Позволяет логировать события и отслеживать работу плагина.

**Методы логирования:**
- `void info(String message, [Map<String, dynamic>? data])` - информационное сообщение
- `void warning(String message, [Map<String, dynamic>? data])` - предупреждение
- `void error(String message, [Object? error, StackTrace? stackTrace])` - ошибка
- `void debug(String message, [Map<String, dynamic>? data])` - отладочное сообщение

**Методы событий:**
- `void onConnect(String config)` - событие подключения
- `void onDisconnect()` - событие отключения
- `void onStatusChanged(String status)` - изменение статуса подключения
- `void onConnectionError(String error)` - ошибка подключения
- `void onSingBoxConnectionStatsChanged(SingBoxConnectionStats stats)` - изменение статистики подключения
- `void onSingBoxSettingsChanged(String key, dynamic value)` - изменение настроек
- `void onSingBoxServerConfigAdded(String configId, String name)` - добавление конфигурации сервера
- `void onSingBoxServerConfigRemoved(String configId)` - удаление конфигурации сервера
- `void onActiveSingBoxServerConfigChanged(String configId)` - смена активной конфигурации

### SingBoxNoOpObserver

Пустая реализация observer (по умолчанию). Все методы не выполняют никаких действий.

### SingBoxTalkerObserver

Observer для интеграции с Talker. Использует dynamic для совместимости без обязательной зависимости.

**Параметры конструктора:**
- `dynamic talker` - экземпляр Talker для логирования
- `String prefix` - префикс для всех логов (по умолчанию `'[SingBox]'`)

## Платформенный интерфейс

### SingBoxPlatform

Абстрактный класс, расширяющий `PlatformInterface`. Определяет все методы, которые должны быть реализованы на платформенном уровне.

**Все методы из класса `SingBox` делегируются к `SingBoxPlatform.instance`.**

### MethodChannelSingBox

Реализация `SingBoxPlatform` через Method Channels.

**Каналы:**
- `methodChannel` - основной канал для вызова методов (`'sing_box'`)
- `statusEventChannel` - канал для событий статуса (`'sing_box/status'`)
- `statsEventChannel` - канал для событий статистики (`'sing_box/stats'`)

**Особенности:**
- Все методы обрабатывают ошибки и возвращают безопасные значения по умолчанию
- Stream'ы обрабатывают ошибки и возвращают значения по умолчанию при сбоях
- Используется `debugPrint` для логирования ошибок в консоль

## Потоки данных (Streams)

### watchSingBoxConnectionStatus()

Возвращает `Stream<SingBoxConnectionStatus>` с обновлениями статуса подключения.

**Источник данных:** Event Channel `'sing_box/status'`

**События:**
- Обновления при каждом изменении статуса подключения
- Обработка ошибок с возвратом `SingBoxConnectionStatus.disconnected` по умолчанию

### watchSingBoxConnectionStats()

Возвращает `Stream<SingBoxConnectionStats>` с обновлениями статистики подключения.

**Источник данных:** Event Channel `'sing_box/stats'`

**События:**
- Постоянные обновления статистики (скорость загрузки/отдачи, байты, пинг, время подключения)
- Обработка ошибок с возвратом пустой статистики по умолчанию

## Обработка ошибок

Все методы класса `SingBox` обрабатывают ошибки следующим образом:

1. **Try-catch блоки** - все асинхронные операции обернуты в try-catch
2. **Observer логирование** - все ошибки логируются через observer
3. **Безопасные значения по умолчанию** - при ошибках возвращаются безопасные значения:
   - `false` для boolean методов
   - `SingBoxConnectionStatus.disconnected` для статуса
   - Пустые объекты статистики с нулевыми значениями
   - Пустые списки для методов, возвращающих списки
   - `null` для nullable типов

## Инициализация

Плагин должен быть инициализирован до использования:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SingBox.instance.initialize();
  runApp(MyApp());
}
```

**Важно:**
- Инициализация должна происходить до старта приложения
- Метод `initialize()` можно вызывать несколько раз (проверка на повторную инициализацию)
- После успешной инициализации флаг `isInitialized` устанавливается в `true`

## Логирование

Логирование осуществляется через Observer Pattern:

1. **Установка observer:**
   ```dart
   final observer = SingBoxTalkerObserver(Talker());
   SingBox.instance.setObserver(observer);
   ```

2. **Создание собственного observer:**
   ```dart
   class MyObserver implements SingBoxObserver {
     // Реализация методов
   }
   SingBox.instance.setObserver(MyObserver());
   ```

3. **События логируются автоматически:**
   - Подключение/отключение
   - Изменения статуса
   - Изменения статистики
   - Изменения настроек
   - Работа с конфигурациями серверов
   - Ошибки

## Расширяемость

Пакет поддерживает расширение через:

1. **Собственные платформенные реализации:**
   - Создать класс, расширяющий `SingBoxPlatform`
   - Установить через `SingBoxPlatform.instance = YourImplementation()`

2. **Собственные Observer:**
   - Реализовать интерфейс `SingBoxObserver`
   - Установить через `SingBox.instance.setObserver(yourObserver)`

3. **Модели данных:**
   - Все модели поддерживают сериализацию/десериализацию через `toMap()` и `fromMap()`
   - Модели поддерживают `copyWith()` для создания копий с изменениями

## Зависимости

- `flutter` - Flutter SDK
- `plugin_platform_interface: ^2.0.2` - для платформенного интерфейса
- `talker` (опционально) - для логирования через SingBoxTalkerObserver

## Методы по категориям

### Инициализация и управление
- `initialize()` - инициализация плагина
- `getPlatformVersion()` - версия платформы
- `setObserver()` - установка observer
- `isInitialized` - проверка инициализации

### Подключение VPN
- `connect()` - подключение к VPN
- `disconnect()` - отключение от VPN
- `switchServer()` - смена сервера

### Статус и статистика
- `getSingBoxConnectionStatus()` - текущий статус
- `getSingBoxConnectionStats()` - текущая статистика
- `watchSingBoxConnectionStatus()` - Stream статуса
- `watchSingBoxConnectionStats()` - Stream статистики

### Измерения
- `testSpeed()` - тест скорости
- `pingCurrentServer()` - пинг текущего сервера
- `pingConfig()` - пинг по конфигу

### Исключения (Bypass)
- `addAppToBypass()` - добавить приложение в исключения
- `removeAppFromBypass()` - удалить приложение из исключений
- `getBypassApps()` - получить список исключенных приложений
- `addDomainToBypass()` - добавить домен в исключения
- `removeDomainFromBypass()` - удалить домен из исключений
- `getBypassDomains()` - получить список исключенных доменов

### Настройки
- `saveSingBoxSettings()` - сохранить настройки
- `loadSingBoxSettings()` - загрузить настройки
- `getSingBoxSettings()` - получить текущие настройки
- `updateSetting()` - обновить отдельный параметр

### Конфигурации серверов
- `addSingBoxServerConfig()` - добавить конфигурацию
- `removeSingBoxServerConfig()` - удалить конфигурацию
- `updateSingBoxServerConfig()` - обновить конфигурацию
- `getSingBoxServerConfigs()` - получить все конфигурации
- `getSingBoxServerConfig()` - получить конфигурацию по ID
- `setActiveSingBoxServerConfig()` - установить активную конфигурацию
- `getActiveSingBoxServerConfig()` - получить активную конфигурацию

### Заблокированные приложения и домены
- `addBlockedApp()` - добавить приложение в блокировку
- `removeBlockedApp()` - удалить приложение из блокировки
- `getBlockedApps()` - получить список заблокированных приложений
- `addBlockedDomain()` - добавить домен в блокировку
- `removeBlockedDomain()` - удалить домен из блокировки
- `getBlockedDomains()` - получить список заблокированных доменов

### Исключенные подсети (Bypass Subnets)
- `addSubnetToBypass()` - добавить подсеть в исключения
- `removeSubnetFromBypass()` - удалить подсеть из исключений
- `getBypassSubnets()` - получить список исключенных подсетей

### DNS серверы
- `addDnsServer()` - добавить DNS сервер
- `removeDnsServer()` - удалить DNS сервер
- `getDnsServers()` - получить список DNS серверов
- `setDnsServers()` - установить DNS серверы (заменить все)

## Всего методов

- **Инициализация:** 2 метода
- **Подключение VPN:** 3 метода
- **Статус и статистика:** 4 метода
- **Измерения:** 3 метода
- **Исключения (Bypass):** 6 методов
- **Исключенные подсети:** 3 метода
- **DNS серверы:** 4 метода
- **Настройки:** 4 метода
- **Конфигурации серверов:** 7 методов
- **Заблокированные:** 6 метода

**Итого: 42 метода API**

