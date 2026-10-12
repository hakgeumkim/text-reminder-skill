import AppKit
import ServiceManagement

let defaults = UserDefaults.standard
let kText = "text"
let kMinutes = "intervalMinutes"
defaults.register(defaults: [kText: "Do what you can, not what you want.", kMinutes: 60])
let lockSeconds = 3

final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// Full-screen text on every screen. Input is blocked for lockSeconds, then any key or click closes it.
@MainActor
final class Overlay {
    private var windows: [NSWindow] = []
    private var hints: [NSTextField] = []
    private var monitor: Any?
    private var countdown: Timer?
    private var remaining = lockSeconds
    private let onClose: () -> Void

    init(text: String, onClose: @escaping () -> Void) {
        self.onClose = onClose
        for screen in NSScreen.screens {
            let window = OverlayWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.setFrame(screen.frame, display: false)
            window.level = .screenSaver
            window.isOpaque = false
            window.backgroundColor = NSColor.black.withAlphaComponent(0.93)
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

            let label = NSTextField(wrappingLabelWithString: text)
            label.font = .systemFont(ofSize: max(36, screen.frame.width / 22), weight: .bold)
            label.textColor = .white
            label.alignment = .center
            let hint = NSTextField(labelWithString: "")
            hint.font = .systemFont(ofSize: 20)
            hint.textColor = NSColor.white.withAlphaComponent(0.5)

            let view = window.contentView!
            for v in [label, hint] {
                v.translatesAutoresizingMaskIntoConstraints = false
                view.addSubview(v)
            }
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                label.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.8),
                hint.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                hint.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -60),
            ])
            windows.append(window)
            hints.append(hint)
        }
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.presentationOptions = [.hideDock, .hideMenuBar, .disableProcessSwitching, .disableHideApplication]
        windows.forEach { $0.makeKeyAndOrderFront(nil) }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            if let self, self.remaining <= 0 { self.close() }
            return nil
        }
        updateHint()
        countdown = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.remaining -= 1
                self.updateHint()
                if self.remaining <= 0 { self.countdown?.invalidate() }
            }
        }
    }

    private func updateHint() {
        let s = remaining > 0 ? "\(remaining)" : "Press any key or click to close"
        hints.forEach { $0.stringValue = s }
    }

    private func close() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        countdown?.invalidate()
        windows.forEach { $0.orderOut(nil) }
        windows = []
        NSApp.presentationOptions = []
        onClose()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let pauseItem = NSMenuItem(title: "Pause", action: #selector(togglePause), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
    private var timer: Timer?
    private var overlay: Overlay?
    private var paused = false
    private var settings: NSWindow?
    private let textField = NSTextField(string: "")
    private let hoursField = NSTextField(string: "")
    private let minutesField = NSTextField(string: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpEditMenu()
        statusItem.button?.image = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: "Text Reminder")
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Now", action: #selector(showNow), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(pauseItem)
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        updateLoginItem()

        // After sleep, start the interval again instead of showing missed reminders.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.schedule() }
        }
        schedule()
    }

    // Without a main menu, Cmd+C/V/X/A/Z do not work in the settings window.
    private func setUpEditMenu() {
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem()
        editItem.submenu = edit
        let main = NSMenu()
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    private func schedule() {
        timer?.invalidate()
        guard !paused, overlay == nil else { return }
        let seconds = TimeInterval(max(1, defaults.integer(forKey: kMinutes)) * 60)
        timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.showNow() }
        }
    }

    @objc private func showNow() {
        timer?.invalidate()
        guard overlay == nil else { return }
        overlay = Overlay(text: defaults.string(forKey: kText) ?? "") { [weak self] in
            self?.overlay = nil
            self?.schedule()
        }
        overlay?.show()
    }

    @objc private func togglePause() {
        paused.toggle()
        pauseItem.title = paused ? "Resume" : "Pause"
        schedule()
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSAlert(error: error).runModal()
        }
        updateLoginItem()
    }

    private func updateLoginItem() {
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func openSettings() {
        if settings == nil { settings = makeSettingsWindow() }
        let minutes = defaults.integer(forKey: kMinutes)
        textField.stringValue = defaults.string(forKey: kText) ?? ""
        hoursField.integerValue = minutes / 60
        minutesField.integerValue = minutes % 60
        NSApp.activate(ignoringOtherApps: true)
        settings?.center()
        settings?.makeKeyAndOrderFront(nil)
    }

    private func makeSettingsWindow() -> NSWindow {
        let formatter = NumberFormatter()
        formatter.minimum = 0
        formatter.allowsFloats = false
        for f in [hoursField, minutesField] {
            f.formatter = formatter
            f.alignment = .right
            f.widthAnchor.constraint(equalToConstant: 50).isActive = true
        }
        textField.usesSingleLineMode = false
        textField.cell?.wraps = true
        textField.widthAnchor.constraint(equalToConstant: 320).isActive = true
        textField.heightAnchor.constraint(equalToConstant: 72).isActive = true

        let interval = NSStackView(views: [hoursField, NSTextField(labelWithString: "hours"), minutesField, NSTextField(labelWithString: "minutes")])
        let save = NSButton(title: "Save", target: self, action: #selector(saveSettings))
        save.keyEquivalent = "\r"
        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Text"), textField],
            [NSTextField(labelWithString: "Every"), interval],
            [NSGridCell.emptyContentView, save],
        ])
        grid.rowSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        grid.translatesAutoresizingMaskIntoConstraints = false

        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Text Reminder Settings"
        window.isReleasedWhenClosed = false
        let view = window.contentView!
        view.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            grid.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
            grid.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
        ])
        return window
    }

    @objc private func saveSettings() {
        let minutes = hoursField.integerValue * 60 + minutesField.integerValue
        let text = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard minutes > 0, !text.isEmpty else { NSSound.beep(); return }
        defaults.set(text, forKey: kText)
        defaults.set(minutes, forKey: kMinutes)
        settings?.close()
        schedule()
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
