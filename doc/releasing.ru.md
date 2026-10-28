# Релиз sing_box (инструкция)

Релиз состоит максимум из двух частей:

1. **Нативное ядро** — GitHub-релиз `libbox-v<LIBBOX_VERSION>` с файлами
   `libbox.aar` и `Libbox.xcframework.zip`. Каждая версия плагина скачивает их
   при сборке и сверяет SHA-256, поэтому они должны существовать **до**
   публикации плагина. Делается один раз на версию sing-box.
2. **Плагин** — версия `x.y.z` из `pubspec.yaml`, публикуется на
   [pub.dev](https://pub.dev/packages/sing_box) автоматически пушем тега
   `vx.y.z` (или GitHub-релизом с этим тегом) либо вручную командой
   `flutter pub publish`.

Английская версия: [releasing.md](releasing.md). В pub-пакет эти файлы не
попадают.

## 0. Разовая настройка

- **Аккаунт pub.dev** — Google-аккаунт, которым загружен `sing_box`
  (`dart pub login` для ручной публикации). По желанию — перенести пакет на
  [verified publisher](https://dart.dev/tools/pub/verified-publishers).
- **Автопубликация** (для релизов по тегу): на
  `https://pub.dev/packages/sing_box/admin` включить *Publishing from GitHub
  Actions*: репозиторий `QUSAD-prod/sing_box`, tag pattern `v{{version}}`,
  *Require GitHub Actions environment* = `pub.dev`. В GitHub: *Settings ->
  Environments -> New environment* `pub.dev`, добавить себя в *Required
  reviewers* — тогда каждая публикация ждёт твоего подтверждения.
- **GitHub CLI** для релиза libbox: `gh auth login`.
- **Имя пакета**: лицензия sing-box запрещает производным работам использовать
  имя без согласия. До первой публичной версии с этим именем напиши автору
  sing-box (contact-sagernet@sekai.icu) и сохрани ответ.

## 1. Подготовка версии

Семантическое версионирование: ломающие изменения API — major, новые
возможности — minor, исправления — patch.

1. Подними версию **везде**:
   - `pubspec.yaml` (`version:`),
   - `ios/sing_box.podspec` и `ios/SingBoxTunnel.podspec` (`s.version`),
   - `android/build.gradle.kts` (`version =`),
   - сниппет установки в `README.md` (`sing_box: ^x.y.z`).
2. Добавь раздел `## x.y.z` в начало `CHANGELOG.md` (Added / Changed / Fixed).
   Без него workflow публикации откажется работать.
3. Если меняется версия sing-box: обнови `LIBBOX_VERSION`, пересобери libbox
   (шаг 3), упомяни новое ядро в CHANGELOG и бейдже README.

```bash
git grep -n -E "version: |s.version|^version = |sing_box: \^" -- pubspec.yaml ios/*.podspec android/build.gradle.kts README.md
```

## 2. Тестирование

Всё прогоняется на релизном коммите. Подробности по каждому набору — в
CONTRIBUTING.md.

```bash
# Статика и unit-тесты (конфиги проверяются настоящим sing-box CLI)
dart format --output=none --set-exit-if-changed lib test example/lib example/integration_test
flutter analyze && (cd example && flutter analyze)
SING_BOX_BIN=/путь/к/sing-box flutter test         # 0 skipped
flutter pub publish --dry-run                       # 0 warnings

# Оценка pub.dev (160/160, когда релизный коммит уже в main)
dart pub global activate pana
dart pub global run pana --no-warning .
```

Сборка sing-box CLI для `SING_BOX_BIN` (один раз на версию):

```bash
git clone --depth 1 --branch v1.14.4 https://github.com/SagerNet/sing-box.git /tmp/sing-box
(cd /tmp/sing-box && go build -trimpath \
  -tags with_gvisor,with_quic,with_wireguard,with_utls,with_clash_api \
  -ldflags "-X github.com/sagernet/sing-box/constant.Version=1.14.4" \
  -o /tmp/sing-box-cli ./cmd/sing-box)
```

Android (эмулятор или устройство):

```bash
cd example
flutter build apk --debug && flutter build apk --release && flutter build appbundle

# e2e: в отдельных терминалах локальные серверы и цикл согласия VPN
SING_BOX_BIN=/tmp/sing-box-cli integration_test/server/run_e2e_server.sh
integration_test/server/grant_vpn_consent.sh
flutter test integration_test/vpn_e2e_test.dart -d emulator-5554 --dart-define=E2E_HOST=10.0.2.2
# перед этим тестом останови цикл согласия
flutter test integration_test/permission_e2e_test.dart -d emulator-5554
```

Затем сценарии жизненного цикла через `lib/e2e_harness.dart`
([doc/android.md](android.md#checking-the-lifecycle-on-a-device)): Back и
смахивание из «Недавних» при подключении, плитка в шторке, старт после
перезагрузки, обновление приложения при подключении, Always-on VPN с
«Блокировать соединения без VPN» (кнопки Stop быть не должно).

iOS:

```bash
cd example
flutter build ios --simulator --debug
flutter test integration_test/smoke_test.dart -d <id симулятора>
flutter build ios --release --no-codesign
# режим CocoaPods: flutter config --no-enable-swift-package-manager, сборка, вернуть обратно
```

На реальном iPhone (платная команда разработчика): подключение и отключение;
неудачный старт (неверный сервер) показывает ошибку ядра; смена сервера на
лету; On Demand и kill switch; перезагрузка с включённым On Demand.

## 3. Релиз libbox

Только если релиза `libbox-v<LIBBOX_VERSION>` ещё нет. В нём должны лежать
**ровно** те файлы, чьи SHA-256 закоммичены.

```bash
# Сборка (или оставь уже имеющиеся build/libbox/, с которых сняты контрольные суммы)
scripts/build_libbox.sh android apple

# Записать их SHA-256 в android/libbox.properties и ios/sing_box/Package.swift
scripts/release_libbox.sh
git add LIBBOX_VERSION android/libbox.properties ios/sing_box/Package.swift
git commit -m "libbox <версия>"

# Создать GitHub-релиз libbox-v<версия> с этими двумя файлами
scripts/release_libbox.sh --publish

# Скачать их обратно и сверить с закреплёнными суммами
scripts/verify_libbox_release.sh
```

**Никогда** не заменяй файлы существующего libbox-релиза другими: уже
опубликованные версии плагина привязаны к старым суммам и перестанут
собираться (`release_libbox.sh` без `--force` откажется). Нужна другая сборка —
выпускай новую версию. Workflow `libbox` только собирает файлы для проверки и
ничего не публикует.

### Без GitHub-релизов

Файлы можно разместить на любом HTTPS-хостинге со структурой
`<base>/libbox-v<версия>/libbox.aar` и
`<base>/libbox-v<версия>/Libbox.xcframework.zip`. Перед публикацией плагина
укажи адрес: `baseUrl` в `android/libbox.properties` (суффикс
`/libbox-v{version}` оставить) и `libboxBaseURL` в
`ios/sing_box/Package.swift`, затем `scripts/verify_libbox_release.sh`.
Разработчики приложений могут переопределить источник при сборке: Android —
`SING_BOX_LIBBOX_AAR` / `SING_BOX_LIBBOX_BASE_URL`, iOS CocoaPods —
`SING_BOX_LIBBOX_XCFRAMEWORK_ZIP` / `SING_BOX_LIBBOX_BASE_URL`, iOS SwiftPM —
локальный `Libbox.xcframework` в плагине.

## 4. Пуш кода

```bash
git push origin 1.0.0                 # релизная ветка
```

Открой pull request в `main`, дождись зелёного CI (анализ, тесты с sing-box
CLI, сборки Android и iOS) и смёрджи. Если в `main` ничего нового нет, можно
fast-forward: `git push origin 1.0.0:main`.

Релиз должен быть в `main` до публикации: pub.dev проверяет, что по адресу
`repository` лежит тот же `pubspec.yaml`.

Нативным сборкам нужен libbox-релиз: пока он не опубликован (шаг 3), job CI
*libbox release* падает с сообщением «libbox.aar is not downloadable», а сборки
Android и iOS пропускаются. Это ожидаемо.

## 5. Публикация на pub.dev

Для одной версии выбирай **один** способ.

### A. Через тег или GitHub-релиз (рекомендую)

```bash
git checkout main && git pull
git tag -a v1.0.0 -m "sing_box 1.0.0"
git push origin v1.0.0
```

или создай GitHub-релиз с новым тегом `v1.0.0` на `main` (*Releases -> Draft a
new release*, в описание — раздел из CHANGELOG). Workflow `Publish to pub.dev`:

1. проверит, что тег = `v` + версия из pubspec и что в CHANGELOG есть раздел;
2. проверит файлы libbox-релиза;
3. прогонит формат, анализ, все тесты (с sing-box CLI) и dry-run;
4. дождётся твоего подтверждения окружения `pub.dev` и опубликует через
   OIDC-токен GitHub (никаких секретов хранить не нужно).

### B. Вручную со своей машины

```bash
git checkout main && git pull
flutter pub publish --dry-run
flutter pub publish                   # покажет список файлов и спросит подтверждение
```

В первый раз `flutter pub publish` откроет браузер для входа. Если
автопубликация включена, не пушь после этого тег `v1.0.0` (workflow попробует
опубликовать ту же версию и упадёт); для отметки используй другой шаблон,
например `release-1.0.0`.

Опубликованные версии неизменяемы. Сломанную версию можно *отозвать*
(retract) на странице admin в течение 7 дней; исправление — всегда новая
версия.

## 6. После публикации

- Проверь https://pub.dev/packages/sing_box: README, CHANGELOG, вкладка
  Example, платформы и оценка (pana отрабатывает через несколько минут).
- Проверь опубликованный пакет в чистом приложении — это проверяет и
  скачивание libbox из релиза:
  ```bash
  flutter create --platforms android,ios vpn_check && cd vpn_check
  flutter pub add sing_box:^1.0.0
  flutter build apk --debug
  ```
- Создай GitHub-релиз `v1.0.0` с текстом из CHANGELOG, если публиковал вручную
  или запушил только тег.

## Если что-то пошло не так

| Проблема | Решение |
| --- | --- |
| Workflow: *Tag … does not match pubspec version* | Удали тег (`git push origin :refs/tags/v1.0.0`), исправь версию, поставь тег заново |
| Workflow: *libbox.aar is not downloadable* | Опубликуй libbox-релиз (шаг 3) |
| Workflow: pub.dev не принимает OIDC-токен | Настройки автопубликации: репозиторий, шаблон `v{{version}}`, имя окружения |
| *Version already exists* | Версии неизменяемы — подними версию |
| Пользователи видят несовпадение sha256 libbox | Файлы релиза подменили: верни исходные или выпусти версию плагина под новый libbox-релиз |
| pana: *Failed to verify repository URL* | В `main` ещё нет опубликованного `pubspec.yaml` |
