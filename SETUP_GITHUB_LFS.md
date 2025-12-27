# Настройка GitHub LFS для Libbox.xcframework

## Проблема

GitHub ограничивает размер файлов в релизах до **25 MB**, а `Libbox.xcframework.zip` весит **72 MB**.

## Решение: GitHub LFS

Используем **GitHub LFS (Large File Storage)** для хранения framework в репозитории.

## Быстрая настройка

### 1. Установите Git LFS (если еще не установлен)

**macOS:**
```bash
brew install git-lfs
```

**Linux:**
```bash
sudo apt-get install git-lfs
```

**Windows:**
Скачайте с https://git-lfs.github.com/

### 2. Настройте LFS в репозитории

```bash
# В корне проекта
./setup_git_lfs.sh

# Или вручную:
git lfs install
git lfs track "ios/Frameworks/Libbox.xcframework/**"
echo "ios/Frameworks/Libbox.xcframework/** filter=lfs diff=lfs merge=lfs -text" >> .gitattributes
```

### 3. Добавьте framework в репозиторий

```bash
# Добавьте .gitattributes
git add .gitattributes

# Добавьте framework (будет загружен через LFS)
git add ios/Frameworks/Libbox.xcframework

# Коммит
git commit -m "Add Libbox.xcframework via Git LFS"

# Пуш (framework будет загружен в LFS)
git push origin main
```

## Проверка

После пуша проверьте, что файл в LFS:

```bash
git lfs ls-files
```

Должен показать файлы из `ios/Frameworks/Libbox.xcframework/`.

## Лимиты GitHub LFS

- **Бесплатный план**: 1 GB хранилища, 1 GB трафика/месяц
- **Framework размер**: ~85 MB
- **Достаточно для**: ~11 загрузок в месяц (бесплатно)

## Создание релиза

После настройки LFS создайте GitHub Release **без** загрузки framework:

```bash
gh release create v0.0.1 \
  --title "sing_box v0.0.1" \
  --notes "Release notes here"
```

Framework будет доступен через скрипт установки, который скачает его из репозитория.

## Альтернатива: Внешний хостинг

Если LFS не подходит, можно использовать:
- AWS S3
- Google Cloud Storage
- Другие CDN

Но это требует дополнительной настройки и может стоить денег.

