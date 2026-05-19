# ServerList — рефакторинг и доработка popover: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Централизовать все мутации состояния серверов в `ServerManager`, устранить баги №1–№3 (потеря объекта `Process`, переполнение pipe-буфера, устаревший захват `index`) и переделать popover в статус-баре под «быстрый доступ».

**Architecture:** Точечный рефакторинг существующей структуры из 6 файлов (структура не меняется). `ServerManager` удерживает объекты `Process` в словаре `[UUID: Process]`, ставит `terminationHandler` и фоновый `Timer` для синхронизации статуса; единый источник ошибок — `@Published lastError`. `AppDelegate` переводит приложение в чистый агент-режим (без окна при старте, переключение activation policy). `ContentView` и `StatusBarPopoverView` ходят за мутациями только в `ServerManager`.

**Tech Stack:** Swift 5.10, SwiftPM (`swift build`), SwiftUI + AppKit, executable target `ServerList`.

---

## ⚠️ Отступление от стандартного TDD (обязательно к прочтению)

Спецификация (`docs/superpowers/specs/2026-05-19-serverlist-refactor-design.md`, раздел «Тестирование») явно фиксирует: проект — это GUI-приложение в виде **executable target** без библиотечного модуля, без модульных тестов и без UI-харнеса; добавление тест-таргета изменило бы `Package.swift` и нарушило требование «Структура файлов не меняется». В этой среде `xcrun` не находит XCTest (подтверждено при baseline-сборке).

Поэтому «тест» в каждой задаче — это **`swift build` (должна проходить без ошибок и без новых предупреждений)** плюс, где задача меняет наблюдаемое поведение, точная ручная проверка. Полный приёмочный чек-лист из спецификации собран в Task 9 и выполняется пользователем на собранном `.app`. Это сознательное, согласованное со спецификацией отклонение от обычного «сначала падающий тест».

Baseline-предупреждение, которое НЕ считается «новым» и которое игнорируем:

```
warning: could not determine XCTest paths: ... xcrun: error: unable to lookup item 'PlatformPath'
```

Это среда, а не наш код. Любое другое предупреждение от компилятора Swift — это регрессия и блокирует задачу.

---

## Структура файлов

| Файл | Ответственность | Изменения в этом плане |
|---|---|---|
| `Sources/Models.swift` | Модель `Server`, `ServerType` | Без изменений |
| `Sources/main.swift` | Точка входа | Без изменений |
| `Sources/ServerManager.swift` | Единственный владелец состояния серверов, жизненного цикла процессов и ошибок | `ServerError`, `lastError`, словарь `processes`, `terminationHandler`, фоновый `Timer`, `deleteServer`, `restartServer`, фикс `checkServerHealth`, `nullDevice` |
| `Sources/AppDelegate.swift` | Жизненный цикл приложения, статус-бар, popover, окно | Агент-режим: нет окна при старте, переключение activation policy, `NSWindowDelegate`, проброс `onQuit` |
| `Sources/ContentView.swift` | Главное окно: добавление/редактирование/список | Удаление и старт/стоп через `ServerManager`, sheet редактирования, alert ошибок, безопасный `URL` |
| `Sources/StatusBarPopoverView.swift` | Popover «быстрый доступ» | Полная переделка: компактные строки, инлайн-ошибки, footer «Открыть окно»/«Выход» |

Баг №4 (жёстко зашитые пути `/opt/homebrew/bin/php`, `/usr/bin/python3`) — **вне скоупа по решению пользователя, не трогаем.**

---

## Task 1: Инициализация контроля версий и фиксация baseline

Проект не под git (`Is a git repository: false`). Это нужно для пошаговых коммитов и отката рефакторинга. Если пользователь явно не хочет git — он может пропустить шаги коммитов во всех задачах; всё остальное останется рабочим.

**Files:**
- Create: `/Users/macbookretina/Documents/Python/servers/.gitignore`

- [ ] **Step 1: Создать `.gitignore`**

Создать файл `/Users/macbookretina/Documents/Python/servers/.gitignore` с содержимым:

```gitignore
.build/
.DS_Store
*.swiftpm
```

- [ ] **Step 2: Инициализировать репозиторий и сделать baseline-коммит**

Run:

```bash
cd /Users/macbookretina/Documents/Python/servers
git init
git add .gitignore FolderServer/Package.swift FolderServer/Sources FolderServer/ServerList.app/Contents/Info.plist docs
git -c user.email=local -c user.name=local commit -m "chore: baseline before ServerList refactor"
```

Expected: создан репозиторий, один коммит с исходным состоянием.

- [ ] **Step 3: Проверить, что baseline-сборка чистая**

Run:

```bash
cd /Users/macbookretina/Documents/Python/servers/FolderServer && swift build 2>&1 | tail -5
```

Expected: `Build complete!` без предупреждений компилятора (кроме игнорируемого XCTest-предупреждения среды, описанного выше).

---

## Task 2: ServerManager — `ServerError`, `lastError`, удержание `Process`, `nullDevice`, `terminationHandler` (баги №1 и №2)

Это ядро багфикса. **Баг №1**: объект `Process` (`task`) локальный — приложение теряет дескриптор, статус рассинхронизируется, внешнюю смерть процесса не видно. Фикс: хранить `Process` в `[UUID: Process]` и ставить `terminationHandler`. **Баг №2**: `Pipe()` для stdout/stderr никогда не вычитывается — буфер pipe (~64 КБ) заполняется, дочерний процесс блокируется на `write`, «болтливый» сервер зависает. Фикс: перенаправить вывод в `FileHandle.nullDevice`.

**Files:**
- Modify: `/Users/macbookretina/Documents/Python/servers/FolderServer/Sources/ServerManager.swift`

- [ ] **Step 1: Добавить тип `ServerError`**

В `Sources/ServerManager.swift` сразу после закрывающей `}` структуры `SystemProcess` (после строки 15) и перед `class ServerManager: ObservableObject {` вставить:

```swift
struct ServerError: Identifiable {
    let id: UUID
    let serverID: UUID
    let message: String
}
```

- [ ] **Step 2: Добавить хранилища состояния в класс**

В `class ServerManager` сразу под строкой `@Published var systemProcesses: [SystemProcess] = []` добавить:

```swift
    @Published var lastError: ServerError?
    private var processes: [UUID: Process] = [:]
    private var healthTimer: Timer?
```

- [ ] **Step 3: Добавить хелперы ошибок**

В `class ServerManager`, сразу после метода `private func notifyServersChanged()` (после его закрывающей `}`), добавить:

```swift
    private func setError(serverID: UUID, message: String) {
        let err = ServerError(id: UUID(), serverID: serverID, message: message)
        if Thread.isMainThread {
            lastError = err
        } else {
            DispatchQueue.main.async { self.lastError = err }
        }
    }

    private func clearError(serverID: UUID) {
        if lastError?.serverID == serverID {
            lastError = nil
        }
    }
```

- [ ] **Step 4: Переписать `startServer` целиком**

Заменить весь метод `startServer(id:)` (текущие строки 109–150, от `func startServer(id: UUID) -> String? {` до его закрывающей `}` перед `func stopServer`) на:

```swift
    func startServer(id: UUID) -> String? {
        guard let index = servers.firstIndex(where: { $0.id == id }) else {
            setError(serverID: id, message: "Сервер не найден")
            return "Сервер не найден"
        }

        let server = servers[index]

        guard isPortAvailable(port: server.port) else {
            let msg = "Порт \(server.port) уже занят"
            setError(serverID: id, message: msg)
            return msg
        }

        guard FileManager.default.fileExists(atPath: server.folderPath) else {
            let msg = "Папка не существует"
            setError(serverID: id, message: msg)
            return msg
        }

        let task = Process()

        switch server.serverType {
        case .php:
            task.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/php")
            task.arguments = ["-S", "localhost:\(server.port)", "-t", server.folderPath]
        case .python:
            task.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            task.arguments = ["-m", "http.server", String(server.port), "--directory", server.folderPath]
        }

        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice

        task.terminationHandler = { [weak self] proc in
            let endedPid = proc.processIdentifier
            DispatchQueue.main.async {
                guard let self = self,
                      let idx = self.servers.firstIndex(where: { $0.id == id }) else { return }
                if self.servers[idx].pid == endedPid {
                    self.servers[idx].isRunning = false
                    self.servers[idx].pid = nil
                    self.processes[id] = nil
                    self.saveServers()
                }
            }
        }

        do {
            try task.run()
        } catch {
            let msg = "Не удалось запустить сервер: \(error.localizedDescription)"
            setError(serverID: id, message: msg)
            return msg
        }

        servers[index].isRunning = true
        servers[index].pid = task.processIdentifier
        processes[id] = task
        clearError(serverID: id)
        saveServers()

        return nil
    }
```

Ключевое: `task` теперь удерживается в `processes[id]` (баг №1); вывод идёт в `nullDevice` (баг №2); `terminationHandler` сбрасывает статус только если сохранённый `pid` совпадает с завершившимся — это защита от затирания уже перезапущенного сервера.

- [ ] **Step 5: Сборка**

Run:

```bash
cd /Users/macbookretina/Documents/Python/servers/FolderServer && swift build 2>&1 | tail -5
```

Expected: `Build complete!` без новых предупреждений.

- [ ] **Step 6: Коммит**

```bash
cd /Users/macbookretina/Documents/Python/servers
git add FolderServer/Sources/ServerManager.swift
git -c user.email=local -c user.name=local commit -m "fix: retain Process, nullDevice output, lastError (bugs #1, #2)"
```

---

## Task 3: ServerManager — фоновый health-Timer, фикс `checkServerHealth` (баг №3), очистка словаря в stop

**Баг №3**: `checkServerHealth(id:)` захватывает `index`, вычисленный *до* `DispatchQueue.main.async`; пока замыкание ждёт, массив `servers` может измениться → мутация не того сервера или выход за границы. Фикс: искать индекс по `id` *внутри* замыкания. Фоновый `Timer` (~5 с) — backstop для процессов из прошлой сессии и убитых извне (например, `kill` из терминала).

Примечание: `checkServerHealth` сейчас нигде не вызывается (проверено `grep`), но спецификация явно требует исправить его захват `index`; активный механизм синхронизации — фоновый `Timer`.

**Files:**
- Modify: `/Users/macbookretina/Documents/Python/servers/FolderServer/Sources/ServerManager.swift`

- [ ] **Step 1: Запустить Timer в `init`**

Заменить метод `init` (текущие строки 23–25):

```swift
    init() {
        loadServers()
    }
```

на:

```swift
    init() {
        loadServers()
        healthTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.pollRunningServers()
        }
    }
```

- [ ] **Step 2: Добавить `pollRunningServers`**

Сразу после переписанного `checkServerHealth` (см. Step 4) добавить новый метод. Чтобы не зависеть от порядка, добавьте этот метод в `class ServerManager` непосредственно перед методом `func scanSystemProcesses() {`:

```swift
    private func pollRunningServers() {
        var changed = false
        for i in servers.indices {
            if servers[i].isRunning, let pid = servers[i].pid, kill(pid, 0) != 0 {
                servers[i].isRunning = false
                servers[i].pid = nil
                processes[servers[i].id] = nil
                changed = true
            }
        }
        if changed { saveServers() }
    }
```

- [ ] **Step 3: Очистить словарь в `stopServer` и `stopAllServers`**

Заменить `stopServer` (текущие строки 152–160):

```swift
    func stopServer(id: UUID) {
        guard let index = servers.firstIndex(where: { $0.id == id }) else { return }
        if let pid = servers[index].pid {
            kill(pid, SIGTERM)
        }
        servers[index].isRunning = false
        servers[index].pid = nil
        saveServers()
    }
```

на:

```swift
    func stopServer(id: UUID) {
        guard let index = servers.firstIndex(where: { $0.id == id }) else { return }
        if let pid = servers[index].pid {
            kill(pid, SIGTERM)
        }
        servers[index].isRunning = false
        servers[index].pid = nil
        processes[id] = nil
        saveServers()
    }
```

Затем в `stopAllServers` (текущие строки 161–172) добавить `processes.removeAll()` перед `saveServers()`. Заменить:

```swift
        for i in servers.indices {
            servers[i].isRunning = false
            servers[i].pid = nil
        }
        saveServers()
    }
```

на:

```swift
        for i in servers.indices {
            servers[i].isRunning = false
            servers[i].pid = nil
        }
        processes.removeAll()
        saveServers()
    }
```

- [ ] **Step 4: Исправить `checkServerHealth` (баг №3)**

Заменить метод `checkServerHealth(id:)` (текущие строки 174–185) целиком на:

```swift
    func checkServerHealth(id: UUID) {
        guard let index = servers.firstIndex(where: { $0.id == id }),
              let pid = servers[index].pid else { return }
        if kill(pid, 0) != 0 {
            DispatchQueue.main.async {
                guard let idx = self.servers.firstIndex(where: { $0.id == id }) else { return }
                self.servers[idx].isRunning = false
                self.servers[idx].pid = nil
                self.processes[id] = nil
                self.saveServers()
            }
        }
    }
```

- [ ] **Step 5: Сборка**

Run:

```bash
cd /Users/macbookretina/Documents/Python/servers/FolderServer && swift build 2>&1 | tail -5
```

Expected: `Build complete!` без новых предупреждений.

- [ ] **Step 6: Коммит**

```bash
cd /Users/macbookretina/Documents/Python/servers
git add FolderServer/Sources/ServerManager.swift
git -c user.email=local -c user.name=local commit -m "fix: backup health timer, fix stale index in checkServerHealth (bug #3)"
```

---

## Task 4: ServerManager — `deleteServer(id:)` и `restartServer(id:)`

`deleteServer` заменяет прямые `servers.removeAll { ... }` из вью (убивает живой процесс перед удалением). `restartServer` заменяет хрупкий `DispatchQueue.main.asyncAfter(0.3)` из popover: останавливает, ждёт освобождения порта (поллинг до ~2 с), стартует.

**Решение по API `restartServer`:** спецификация упоминала возврат `String?`, но перезапуск по своей природе асинхронный (ожидание освобождения порта), поэтому синхронный возврат ошибки был бы недостоверным. Ошибки идут через `lastError` — это единый источник ошибок, который сама спецификация назначает каноническим для окна и popover. Поэтому `restartServer(id:)` возвращает `Void`. Это сознательное согласованное решение.

**Files:**
- Modify: `/Users/macbookretina/Documents/Python/servers/FolderServer/Sources/ServerManager.swift`

- [ ] **Step 1: Добавить `deleteServer` и `restartServer`**

В `class ServerManager` сразу после метода `stopAllServers()` (после его закрывающей `}`) и перед `func checkServerHealth` добавить:

```swift
    func deleteServer(id: UUID) {
        if let index = servers.firstIndex(where: { $0.id == id }),
           servers[index].isRunning, let pid = servers[index].pid {
            kill(pid, SIGTERM)
        }
        processes[id] = nil
        servers.removeAll { $0.id == id }
        if lastError?.serverID == id { lastError = nil }
        saveServers()
    }

    func restartServer(id: UUID) {
        guard let server = servers.first(where: { $0.id == id }) else {
            setError(serverID: id, message: "Сервер не найден")
            return
        }
        let port = server.port

        if server.isRunning {
            stopServer(id: id)
        }

        let deadline = Date().addingTimeInterval(2.0)

        func attempt() {
            if isPortAvailable(port: port) {
                _ = startServer(id: id)
            } else if Date() < deadline {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { attempt() }
            } else {
                setError(serverID: id, message: "Порт \(port) не освободился, перезапуск отменён")
            }
        }

        attempt()
    }
```

- [ ] **Step 2: Сборка**

Run:

```bash
cd /Users/macbookretina/Documents/Python/servers/FolderServer && swift build 2>&1 | tail -5
```

Expected: `Build complete!` без новых предупреждений.

- [ ] **Step 3: Коммит**

```bash
cd /Users/macbookretina/Documents/Python/servers
git add FolderServer/Sources/ServerManager.swift
git -c user.email=local -c user.name=local commit -m "feat: add deleteServer and restartServer to ServerManager"
```

---

## Task 5: AppDelegate — чистый агент-режим

Приложение должно стартовать только в статус-баре: без окна, без иконки в Dock. Окно открывается по кнопке; при его закрытии возвращается агент-режим. `LSUIElement` в `Info.plist` уже `true`, поэтому приложение и так стартует accessory — но мы явно убираем показ окна при старте и явно управляем activation policy при открытии/закрытии окна.

**Files:**
- Modify: `/Users/macbookretina/Documents/Python/servers/FolderServer/Sources/AppDelegate.swift`

- [ ] **Step 1: Добавить conformance `NSWindowDelegate`**

Заменить строку 4:

```swift
class AppDelegate: NSObject, NSApplicationDelegate {
```

на:

```swift
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
```

- [ ] **Step 2: Не показывать окно при старте, назначить делегата окна**

В `applicationDidFinishLaunching` заменить строку 30:

```swift
        window.makeKeyAndOrderFront(nil)
    }
```

на:

```swift
        window.delegate = self
        NSApp.setActivationPolicy(.accessory)
    }
```

(Окно создаётся и держится в `window`, но не показывается.)

- [ ] **Step 3: Пробросить `onQuit` в popover**

В `setupPopover()` заменить блок создания `popoverContent` (текущие строки 50–59):

```swift
        let popoverContent = StatusBarPopoverView(
            serverManager: serverManager,
            onClose: { [weak self] in
                self?.closePopover()
            },
            onOpenApp: { [weak self] in
                self?.openApp()
                self?.closePopover()
            }
        )
```

на:

```swift
        let popoverContent = StatusBarPopoverView(
            serverManager: serverManager,
            onClose: { [weak self] in
                self?.closePopover()
            },
            onOpenApp: { [weak self] in
                self?.openApp()
                self?.closePopover()
            },
            onQuit: { [weak self] in
                self?.quitApp()
            }
        )
```

- [ ] **Step 4: `openApp` переключает в обычный режим; добавить `windowWillClose`**

Заменить метод `openApp` (текущие строки 98–101):

```swift
    @objc func openApp() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
```

на:

```swift
    @objc func openApp() {
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
```

(`quitApp()` уже останавливает все серверы и вызывает `NSApp.terminate(nil)` — менять не нужно, теперь он привязан к кнопке «Выход» в popover через `onQuit`.)

- [ ] **Step 5: Сборка**

Run:

```bash
cd /Users/macbookretina/Documents/Python/servers/FolderServer && swift build 2>&1 | tail -5
```

Expected: сборка упадёт с ошибкой вида `extra argument 'onQuit' in call` — потому что `StatusBarPopoverView` ещё не принимает `onQuit`. Это ожидаемо; параметр будет добавлен в Task 7. Зафиксируйте этот файл и продолжайте; зелёная сборка восстановится в конце Task 7.

- [ ] **Step 6: Коммит**

```bash
cd /Users/macbookretina/Documents/Python/servers
git add FolderServer/Sources/AppDelegate.swift
git -c user.email=local -c user.name=local commit -m "feat: agent-mode window lifecycle in AppDelegate"
```

---

## Task 6: ContentView — мутации через ServerManager, sheet редактирования, alert ошибок, безопасный URL

Подключает мёртвый `updateServer` через sheet редактирования, убирает прямой `servers.removeAll`, показывает ошибки через `.alert(item:)` на `lastError`, убирает force-unwrap `URL(string:)!` в двух местах.

**Files:**
- Modify: `/Users/macbookretina/Documents/Python/servers/FolderServer/Sources/ContentView.swift`

- [ ] **Step 1: Добавить `@State` для редактируемого сервера**

В `struct ContentView` после строки `@State private var showSystemProcesses: Bool = false` добавить:

```swift
    @State private var editingServer: Server?
```

- [ ] **Step 2: Привязать alert и sheet редактирования к `body`**

Заменить `body` (текущие строки 14–22):

```swift
    var body: some View {
        VStack(spacing: 0) {
            formSection
            Divider()
            serversListSection
        }
        .frame(width: 520, height: 450)
        .background(Color(NSColor.windowBackgroundColor))
    }
```

на:

```swift
    var body: some View {
        VStack(spacing: 0) {
            formSection
            Divider()
            serversListSection
        }
        .frame(width: 520, height: 450)
        .background(Color(NSColor.windowBackgroundColor))
        .alert(item: $serverManager.lastError) { err in
            Alert(
                title: Text("Ошибка"),
                message: Text(err.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .sheet(item: $editingServer) { server in
            EditServerView(serverManager: serverManager, server: server)
        }
    }
```

- [ ] **Step 3: Прокинуть `onEdit` в строку списка**

Заменить блок `CompactServerRow(...)` внутри `serversListSection` (текущие строки 81–86):

```swift
                        CompactServerRow(
                            server: server,
                            onStart: { _ = serverManager.startServer(id: server.id) },
                            onStop: { serverManager.stopServer(id: server.id) },
                            onDelete: { deleteServer(id: server.id) }
                        )
```

на:

```swift
                        CompactServerRow(
                            server: server,
                            onStart: { _ = serverManager.startServer(id: server.id) },
                            onStop: { serverManager.stopServer(id: server.id) },
                            onEdit: { editingServer = server },
                            onDelete: { deleteServer(id: server.id) }
                        )
```

- [ ] **Step 4: Удаление через ServerManager**

Заменить `deleteServer` (текущие строки 103–105):

```swift
    private func deleteServer(id: UUID) {
        serverManager.servers.removeAll { $0.id == id }
    }
```

на:

```swift
    private func deleteServer(id: UUID) {
        serverManager.deleteServer(id: id)
    }
```

- [ ] **Step 5: Добавить кнопку «редактировать» и безопасный URL в `CompactServerRow`**

В `struct CompactServerRow` заменить блок свойств-замыканий (текущие строки 109–112):

```swift
    let server: Server
    let onStart: () -> Void
    let onStop: () -> Void
    let onDelete: () -> Void
```

на:

```swift
    let server: Server
    let onStart: () -> Void
    let onStop: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
```

Затем заменить кнопку браузера (текущие строки 151–156):

```swift
                Button(action: { NSWorkspace.shared.open(URL(string: "http://localhost:\(server.port)")!) }) {
                    Image(systemName: "safari")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
```

на:

```swift
                Button(action: {
                    if let url = URL(string: "http://localhost:\(server.port)") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    Image(systemName: "safari")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
```

Затем добавить кнопку редактирования. Заменить кнопку удаления (текущие строки 174–180):

```swift
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.red)
```

на:

```swift
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.red)
```

- [ ] **Step 6: Безопасный URL в `SystemProcessRowView`**

Заменить кнопку браузера в `SystemProcessRowView` (текущие строки 320–324):

```swift
            Button(action: { NSWorkspace.shared.open(URL(string: "http://localhost:\(process.port)")!) }) {
                Image(systemName: "safari")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
```

на:

```swift
            Button(action: {
                if let url = URL(string: "http://localhost:\(process.port)") {
                    NSWorkspace.shared.open(url)
                }
            }) {
                Image(systemName: "safari")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
```

- [ ] **Step 7: Добавить `EditServerView`**

В конец файла `Sources/ContentView.swift` (после закрывающей `}` структуры `SystemProcessRowView`) добавить:

```swift
struct EditServerView: View {
    @ObservedObject var serverManager: ServerManager
    let server: Server
    @Environment(\.dismiss) var dismiss

    @State private var name: String
    @State private var serverType: ServerType
    @State private var folderPath: String
    @State private var port: String

    init(serverManager: ServerManager, server: Server) {
        self.serverManager = serverManager
        self.server = server
        _name = State(initialValue: server.name)
        _serverType = State(initialValue: server.serverType)
        _folderPath = State(initialValue: server.folderPath)
        _port = State(initialValue: String(server.port))
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("Редактировать сервер")
                .font(.headline)
                .padding(.top)

            Form {
                TextField("Название", text: $name)
                Picker("Тип", selection: $serverType) {
                    ForEach(ServerType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                HStack {
                    TextField("Папка", text: $folderPath)
                    Button("Обзор...") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = false
                        panel.canChooseDirectories = true
                        panel.allowsMultipleSelection = false
                        panel.canCreateDirectories = false
                        if panel.runModal() == .OK, let url = panel.url {
                            folderPath = url.path
                        }
                    }
                }
                TextField("Порт", text: $port)
            }
            .padding(.horizontal)

            HStack {
                Button("Отмена") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Сохранить") {
                    guard let portNum = Int(port), portNum >= 1024, portNum <= 65535 else { return }
                    serverManager.updateServer(
                        id: server.id,
                        name: name.isEmpty ? "Сервер" : name,
                        serverType: serverType,
                        folderPath: folderPath,
                        port: portNum
                    )
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(folderPath.isEmpty || port.isEmpty)
            }
            .padding(.bottom)
        }
        .frame(width: 420, height: 280)
    }
}
```

- [ ] **Step 8: Сборка**

Run:

```bash
cd /Users/macbookretina/Documents/Python/servers/FolderServer && swift build 2>&1 | tail -5
```

Expected: всё ещё ошибка `extra argument 'onQuit' in call` из Task 5 (StatusBarPopoverView пока без `onQuit`). Других ошибок быть не должно. Если есть другие ошибки компиляции — это регрессия в этой задаче, исправьте до коммита.

- [ ] **Step 9: Коммит**

```bash
cd /Users/macbookretina/Documents/Python/servers
git add FolderServer/Sources/ContentView.swift
git -c user.email=local -c user.name=local commit -m "feat: edit sheet, error alert, ServerManager delete, safe URL in ContentView"
```

---

## Task 7: StatusBarPopoverView — переделка под «быстрый доступ»

Полная переделка popover: компактные строки (точка статуса, имя, `:порт`), кнопки старт/стоп, перезапуск и браузер (последние две — только когда сервер работает), инлайн-ошибка под именем из `lastError`, footer «Открыть окно» / «Выход», пустое состояние с подсказкой. Удаление, редактирование, список системных процессов и открытие папки в popover отсутствуют — это остаётся в главном окне (роль popover по спецификации). После этой задачи сборка снова зелёная.

Раскладка-ориентир (из спецификации):

```
┌─ ServerList ──────────────────┐
│  ● Мой сайт      :8080         │
│              [↻] [🌐] [■]      │
│ ───────────────────────────── │
│  ○ API           :3000   [▶]   │
│ ───────────────────────────── │
│  ⚠ Docs — порт 4000 занят      │
│                          [▶]   │
│ ───────────────────────────── │
│ [ Открыть окно ]   [ Выход ]   │
└────────────────────────────────┘
```

**Files:**
- Modify (полная замена содержимого): `/Users/macbookretina/Documents/Python/servers/FolderServer/Sources/StatusBarPopoverView.swift`

- [ ] **Step 1: Заменить содержимое файла целиком**

Полностью перезаписать `Sources/StatusBarPopoverView.swift` следующим содержимым:

```swift
import SwiftUI
import AppKit

struct StatusBarPopoverView: View {
    @ObservedObject var serverManager: ServerManager
    let onClose: () -> Void
    let onOpenApp: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            serversList
            Divider()
            footer
        }
        .frame(width: 320, height: 400)
    }

    private var header: some View {
        HStack {
            Text("ServerList")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var serversList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if serverManager.servers.isEmpty {
                    VStack(spacing: 6) {
                        Text("Нет серверов")
                            .foregroundColor(.secondary)
                        Text("Откройте окно, чтобы добавить сервер")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 240)
                } else {
                    ForEach(serverManager.servers) { server in
                        ServerPopoverRow(
                            server: server,
                            errorMessage: serverManager.lastError?.serverID == server.id
                                ? serverManager.lastError?.message
                                : nil,
                            onToggle: {
                                if server.isRunning {
                                    serverManager.stopServer(id: server.id)
                                } else {
                                    _ = serverManager.startServer(id: server.id)
                                }
                            },
                            onRestart: {
                                serverManager.restartServer(id: server.id)
                            },
                            onOpenBrowser: {
                                if let url = URL(string: "http://localhost:\(server.port)") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        )
                        Divider()
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 0) {
            Button(action: onOpenApp) {
                HStack(spacing: 4) {
                    Image(systemName: "macwindow")
                        .font(.system(size: 12))
                    Text("Открыть окно")
                        .font(.system(size: 12))
                }
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            Divider()

            Button(action: onQuit) {
                HStack(spacing: 4) {
                    Image(systemName: "power")
                        .font(.system(size: 12))
                    Text("Выход")
                        .font(.system(size: 12))
                }
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct ServerPopoverRow: View {
    let server: Server
    let errorMessage: String?
    let onToggle: () -> Void
    let onRestart: () -> Void
    let onOpenBrowser: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Circle()
                    .fill(server.isRunning ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)

                Text(server.name)
                    .font(.system(size: 13))
                    .lineLimit(1)

                Text(":\(server.port)")
                    .font(.system(size: 12))
                    .foregroundColor(.blue)

                Spacer()

                HStack(spacing: 10) {
                    if server.isRunning {
                        Button(action: onRestart) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12))
                                .foregroundColor(.orange)
                        }
                        .buttonStyle(.plain)
                        .help("Перезапустить")

                        Button(action: onOpenBrowser) {
                            Image(systemName: "safari")
                                .font(.system(size: 12))
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                        .help("Открыть в браузере")
                    }

                    Button(action: onToggle) {
                        Image(systemName: server.isRunning ? "stop.fill" : "play.fill")
                            .font(.system(size: 12))
                            .foregroundColor(server.isRunning ? .red : .green)
                    }
                    .buttonStyle(.plain)
                    .help(server.isRunning ? "Остановить" : "Запустить")
                }
            }

            if let errorMessage = errorMessage {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                    Text(errorMessage)
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                        .lineLimit(2)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor))
    }
}
```

Примечание: параметр `onClose` оставлен в сигнатуре (его передаёт `AppDelegate`), хотя footer его больше не использует — закрытие popover по клику вне обеспечивает существующий `.transient` + глобальный event monitor в `AppDelegate`. Неиспользуемое хранимое свойство структуры не вызывает предупреждений Swift.

- [ ] **Step 2: Сборка — теперь должна быть зелёной**

Run:

```bash
cd /Users/macbookretina/Documents/Python/servers/FolderServer && swift build 2>&1 | tail -5
```

Expected: `Build complete!` без ошибок и без новых предупреждений. Ошибка `onQuit` из Task 5/6 устранена.

- [ ] **Step 3: Коммит**

```bash
cd /Users/macbookretina/Documents/Python/servers
git add FolderServer/Sources/StatusBarPopoverView.swift
git -c user.email=local -c user.name=local commit -m "feat: redesign popover as quick-access panel with inline errors"
```

---

## Task 8: Чистая релизная сборка и установка в .app

Собрать релизный бинарник без предупреждений и поставить его в `ServerList.app`, чтобы пользователь мог пройти приёмочный чек-лист.

**Files:**
- Modify (только бинарник внутри бандла): `/Users/macbookretina/Documents/Python/servers/FolderServer/ServerList.app/Contents/MacOS/ServerList`

- [ ] **Step 1: Релизная сборка с проверкой предупреждений**

Run:

```bash
cd /Users/macbookretina/Documents/Python/servers/FolderServer && swift build -c release 2>&1 | tee /tmp/serverlist-build.log | tail -5
```

Expected: `Build complete!`. Затем проверить отсутствие предупреждений компилятора:

```bash
grep -i "warning:" /tmp/serverlist-build.log | grep -v "could not determine XCTest paths" | grep -v "PlatformPath"
```

Expected: пустой вывод (никаких предупреждений нашего кода). Если что-то выведено — это регрессия, исправить до продолжения.

- [ ] **Step 2: Установить бинарник в бандл**

Run:

```bash
cp /Users/macbookretina/Documents/Python/servers/FolderServer/.build/release/ServerList \
   /Users/macbookretina/Documents/Python/servers/FolderServer/ServerList.app/Contents/MacOS/ServerList
```

Expected: команда завершается без ошибок.

- [ ] **Step 3: Коммит**

```bash
cd /Users/macbookretina/Documents/Python/servers
git add FolderServer/ServerList.app/Contents/MacOS/ServerList
git -c user.email=local -c user.name=local commit -m "build: install release binary into ServerList.app"
```

---

## Task 9: Приёмочный ручной чек-лист (выполняет пользователь)

Автотестов нет (см. отступление в начале плана). Это приёмка из раздела «Тестирование» спецификации. Запустить приложение:

```bash
open /Users/macbookretina/Documents/Python/servers/FolderServer/ServerList.app
```

- [ ] Приложение стартует без окна и без иконки в Dock; иконка в статус-баре есть.
- [ ] «Открыть окно» (footer popover) открывает и фокусирует окно; закрытие окна возвращает агент-режим (иконка из Dock исчезает).
- [ ] Старт сервера (▶ в popover) → точка зелёная, сайт доступен в браузере (🌐).
- [ ] Стоп (■) → точка серая; `lsof -i :<порт>` пусто.
- [ ] Перезапуск (↻, виден только у работающего) → сервер снова доступен, без дубля процесса (`lsof -i :<порт>` — ровно один PID).
- [ ] Удаление работающего сервера из главного окна (🗑) → процесс убит; сервер не возвращается после перезапуска приложения.
- [ ] Редактирование сервера из главного окна (✏️) → sheet с полями, после «Сохранить» изменения видны и сохраняются между запусками.
- [ ] Старт на занятом порту → alert в окне И инлайн-строка с ⚠ под именем сервера в popover.
- [ ] «Болтливый» сервер (много запросов/логов) → не зависает, остаётся доступен.
- [ ] Внешнее убийство процесса (`kill <pid>` из терминала) → статус в приложении становится серым в течение ~5 с.
- [ ] «Выход» из popover завершает приложение и останавливает все серверы (`lsof -i` по их портам пусто).

Соответствие задачам: пункты 1–2 → Task 5; 3–5 → Tasks 2–4; 6–7 → Tasks 4, 6; 8 → Tasks 2, 6, 7; 9 → Task 2 (баг №2); 10 → Task 3 (фоновый Timer); 11 → существующий `quitApp` + Task 5.

---

## Соответствие спецификации (self-review)

| Требование спецификации | Задача |
|---|---|
| `deleteServer(id:)` вместо `servers.removeAll` во вью | Task 4 (метод), Task 6 (ContentView), Task 7 (popover больше не удаляет) |
| `restartServer(id:)` вместо `asyncAfter(0.3)` | Task 4, Task 7 |
| Словарь `[UUID: Process]`, удержание процессов (баг №1) | Task 2 |
| `terminationHandler` с проверкой совпадения pid | Task 2 |
| `stdout/stderr` → `nullDevice` (баг №2) | Task 2 |
| Фоновый `Timer` (~5 с) | Task 3 |
| Фикс захвата `index` в `checkServerHealth` (баг №3) | Task 3 |
| `@Published lastError: ServerError?` (Identifiable) | Task 2 |
| AppDelegate: нет окна при старте | Task 5 |
| AppDelegate: activation policy open/close, `windowWillClose` | Task 5 |
| AppDelegate: «Выход» = полный quit, привязка к popover | Task 5 (`onQuit`), Task 7 |
| ContentView: sheet редактирования (подключение `updateServer`) | Task 6 |
| ContentView: `.alert(item: $serverManager.lastError)` | Task 6 |
| Безопасный `URL` вместо `URL(string:)!` | Task 6 (2 места), Task 7 (popover) |
| Popover: компактные строки, старт/стоп/↻/🌐, инлайн-ошибка, footer, пустое состояние | Task 7 |
| Баг №4 (пути PHP/Python) НЕ трогаем | Соблюдено: пути в `startServer` оставлены без изменений |
| Добавление/удаление/системные процессы — только в окне | Соблюдено: popover их не содержит (Task 7) |
| Структура файлов не меняется | Соблюдено: ни одного нового исходного файла, только `.gitignore` |

---

**Plan complete and saved to `docs/superpowers/plans/2026-05-19-serverlist-refactor.md`. Two execution options:**

**1. Subagent-Driven (recommended)** — я запускаю свежего субагента на каждую задачу, ревью между задачами, быстрая итерация.

**2. Inline Execution** — выполняю задачи в этой сессии через executing-plans, пакетно с чекпоинтами для ревью.

**Какой подход?**
