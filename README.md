# ServerList

ServerList - небольшое приложение для macOS в строке меню. Оно запускает и останавливает локальные серверы разработки из выбранных папок.

## Скачать

[Скачать последнюю версию ServerList.zip](../../releases/latest/download/ServerList.zip)

После скачивания:

1. Распакуйте `ServerList.zip`.
2. Перенесите `ServerList.app` в папку `Applications`.
3. Запустите приложение. Иконка появится в строке меню macOS.

Если macOS предупреждает, что приложение не удалось проверить, откройте `System Settings` -> `Privacy & Security` и разрешите запуск вручную.

## Возможности

- Запуск встроенного PHP-сервера: `php -S localhost:<port> -t <folder>`.
- Запуск статического Python-сервера: `python3 -m http.server <port> --directory <folder>`.
- Быстрые действия из строки меню: запуск, остановка, перезапуск и открытие в браузере.
- Сохранение профилей серверов в macOS `UserDefaults`.
- Обнаружение уже запущенных локальных PHP/Python-серверов.

Интерфейс приложения сейчас на русском языке.

## Требования

- macOS 12 или новее.
- Python 3 по пути `/usr/bin/python3`.
- PHP по пути `/opt/homebrew/bin/php`, если нужны PHP-серверы.

## Сборка из исходников

Этот раздел нужен только разработчикам. Если вы просто хотите пользоваться приложением, скачайте готовый архив из раздела [Скачать](#скачать).

Установите Xcode Command Line Tools:

```bash
xcode-select --install
```

Соберите приложение:

```bash
./scripts/build-app.sh
```

Готовые файлы появятся здесь:

```text
dist/ServerList.app
dist/ServerList.zip
```

Запуск локальной сборки:

```bash
open dist/ServerList.app
```

## Разработка

Работа напрямую через SwiftPM:

```bash
cd FolderServer
swift build
swift run ServerList
```

Генерация Xcode-проекта через XcodeGen:

```bash
cd FolderServer
xcodegen generate
open ServerList.xcodeproj
```

## Примечания

ServerList работает как menu bar app: приложение запускается без иконки в Dock, а главное окно открывается из выпадающего меню в строке меню.

Автоматический поиск PHP пока не реализован. На Mac с Apple Silicon и Homebrew ожидается путь `/opt/homebrew/bin/php`.

## Лицензия

MIT
