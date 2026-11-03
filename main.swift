import AppKit
import ServiceManagement

let defaults = UserDefaults.standard
let kText = "text"
let kMinutes = "intervalMinutes"
let kActiveHours = "activeHoursEnabled"
let kActiveStart = "activeHoursStartMinute"
let kActiveEnd = "activeHoursEndMinute"
defaults.register(defaults: [kText: "Do what you can, not what you want.", kMinutes: 60,
                             kActiveHours: false, kActiveStart: 9 * 60, kActiveEnd: 22 * 60])
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
        guard !windows.isEmpty else { close(); return }
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

    func close() {
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
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let pauseItem = NSMenuItem(title: "Pause", action: #selector(togglePause), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
    private let nextItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private var timer: Timer?
    private var boundaryTimer: Timer?
    private var nextReminder: Date?
    private var overlay: Overlay?
    private var automaticOverlay = false
    private var paused = false
    private var sleeping = false
    private var settings: NSWindow?
    private let textField = NSTextField(string: "")
    private let hoursField = NSTextField(string: "")
    private let minutesField = NSTextField(string: "")
    private let activeHoursButton = NSButton(checkboxWithTitle: "Enable Active Hours", target: nil, action: nil)
    private let startPicker = NSDatePicker()
    private let endPicker = NSDatePicker()
    private let timeZoneLabel = NSTextField(labelWithString: "")
    private let validationLabel = NSTextField(wrappingLabelWithString: "")

    private var activeHours: ActiveHours? {
        guard defaults.bool(forKey: kActiveHours) else { return nil }
        return ActiveHours(startMinute: defaults.integer(forKey: kActiveStart),
                           endMinute: defaults.integer(forKey: kActiveEnd))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpEditMenu()
        statusItem.button?.image = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: "Text Reminder")
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(nextItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Show Now", action: #selector(showNow), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(pauseItem)
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        updateLoginItem()

        // Invalidate before sleep so an overdue callback cannot show a missed reminder.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.sleeping = true
                self?.restartSchedule()
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.sleeping = false
                self?.restartSchedule()
            }
        }
        for name in [NSNotification.Name.NSSystemTimeZoneDidChange, NSNotification.Name.NSSystemClockDidChange] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    NSTimeZone.resetSystemTimeZone()
                    self?.refreshPickerTimeZone()
                    self?.schedule()
                }
            }
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
        boundaryTimer?.invalidate()
        nextReminder = nil
        let now = Date()
        let calendar = Calendar.autoupdatingCurrent
        if automaticOverlay && (paused || sleeping || activeHours.map({ $0.window(containing: now, calendar: calendar) == nil }) == true) {
            overlay?.close()
            return
        }
        defer { updateStatus() }
        guard !paused, !sleeping else { return }
        if let boundary = activeHours?.nextBoundary(after: now, calendar: calendar) {
            boundaryTimer = makeTimer(at: boundary) { [weak self] in self?.schedule() }
        }
        guard overlay == nil else { return }
        let seconds = TimeInterval(max(1, defaults.integer(forKey: kMinutes))) * 60
        if let hours = activeHours {
            nextReminder = hours.nextReminder(after: now, interval: seconds,
                                               minimumDisplay: TimeInterval(lockSeconds), calendar: calendar)
        } else {
            nextReminder = now.addingTimeInterval(seconds)
        }
        if let nextReminder {
            timer = makeTimer(at: nextReminder) { [weak self] in self?.showAutomaticReminder() }
        }
    }

    private func makeTimer(at date: Date, action: @escaping @MainActor () -> Void) -> Timer {
        let timer = Timer(fire: date, interval: 0, repeats: false) { _ in
            MainActor.assumeIsolated { action() }
        }
        // Boundary enforcement must also run while a menu is tracking input.
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    private func restartSchedule() {
        if automaticOverlay { overlay?.close() } else { schedule() }
    }

    private func showAutomaticReminder() {
        guard !paused, !sleeping, overlay == nil else { schedule(); return }
        if let hours = activeHours,
           !hours.permitsReminder(at: Date(), minimumDisplay: TimeInterval(lockSeconds), calendar: .autoupdatingCurrent) {
            schedule()
            return
        }
        showOverlay(automatic: true)
    }

    @objc private func showNow() {
        // An explicit preview is available even when automatic reminders are paused or outside hours.
        showOverlay(automatic: false)
    }

    private func showOverlay(automatic: Bool) {
        guard overlay == nil else { return }
        timer?.invalidate()
        nextReminder = nil
        automaticOverlay = automatic
        overlay = Overlay(text: defaults.string(forKey: kText) ?? "") { [weak self] in
            self?.overlay = nil
            self?.automaticOverlay = false
            self?.schedule()
        }
        overlay?.show()
        updateStatus()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        updateStatus()
    }

    private func updateStatus() {
        let now = Date()
        let calendar = Calendar.autoupdatingCurrent
        let state: String
        if paused {
            state = "Paused"
        } else if sleeping {
            state = "Sleeping"
        } else if overlay != nil {
            state = automaticOverlay ? "Reminder on screen" : "Preview on screen"
        } else if let hours = activeHours {
            state = hours.window(containing: now, calendar: calendar) == nil
                ? "Outside active hours" : "Active hours"
        } else {
            state = "Automatic reminders on"
        }

        let detail: String
        if let nextReminder {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .autoupdatingCurrent
            formatter.dateFormat = "HH:mm"
            let time = formatter.string(from: nextReminder)
            if calendar.isDate(nextReminder, inSameDayAs: now) {
                nextItem.title = time
            } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
                      calendar.isDate(nextReminder, inSameDayAs: tomorrow) {
                nextItem.title = "Tomorrow \(time)"
            } else {
                formatter.dateFormat = "MM/dd HH:mm"
                nextItem.title = formatter.string(from: nextReminder)
            }
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            detail = "\(state)\nNext reminder: \(formatter.string(from: nextReminder))"
        } else {
            if paused {
                nextItem.title = "Paused"
            } else if sleeping {
                nextItem.title = "Sleeping"
            } else if overlay != nil {
                nextItem.title = automaticOverlay ? "Reminder" : "Preview"
            } else {
                nextItem.title = "Check Settings"
            }
            detail = state
        }
        nextItem.toolTip = detail
        statusItem.button?.toolTip = detail
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
        activeHoursButton.state = defaults.bool(forKey: kActiveHours) ? .on : .off
        setTime(defaults.integer(forKey: kActiveStart), on: startPicker)
        setTime(defaults.integer(forKey: kActiveEnd), on: endPicker)
        validationLabel.stringValue = ""
        updateActiveHoursControls()
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

        activeHoursButton.target = self
        activeHoursButton.action = #selector(updateActiveHoursControls)
        for picker in [startPicker, endPicker] {
            picker.datePickerStyle = .textFieldAndStepper
            picker.datePickerElements = .hourMinute
            picker.widthAnchor.constraint(equalToConstant: 110).isActive = true
        }
        startPicker.setAccessibilityLabel("Active hours start")
        endPicker.setAccessibilityLabel("Active hours end")
        timeZoneLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        timeZoneLabel.textColor = .secondaryLabelColor
        let hint = NSTextField(wrappingLabelWithString: "Daily, including overnight hours. Show Now works anytime.\nThe first reminder comes one interval after active hours begin.")
        hint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        hint.textColor = .secondaryLabelColor
        hint.widthAnchor.constraint(equalToConstant: 320).isActive = true
        validationLabel.textColor = .systemRed
        validationLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        validationLabel.widthAnchor.constraint(equalToConstant: 320).isActive = true
        validationLabel.heightAnchor.constraint(equalToConstant: 44).isActive = true
        let times = NSStackView(views: [startPicker, NSTextField(labelWithString: "to"), endPicker])

        let interval = NSStackView(views: [hoursField, NSTextField(labelWithString: "hours"), minutesField, NSTextField(labelWithString: "minutes")])
        let save = NSButton(title: "Save", target: self, action: #selector(saveSettings))
        save.keyEquivalent = "\r"
        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Text"), textField],
            [NSTextField(labelWithString: "Every"), interval],
            [NSTextField(labelWithString: "Active Hours"), activeHoursButton],
            [NSGridCell.emptyContentView, times],
            [NSGridCell.emptyContentView, timeZoneLabel],
            [NSGridCell.emptyContentView, hint],
            [NSGridCell.emptyContentView, validationLabel],
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
        window.setContentSize(view.fittingSize)
        return window
    }

    @objc private func saveSettings() {
        settings?.makeFirstResponder(nil)
        let (hours, overflowHours) = hoursField.integerValue.multipliedReportingOverflow(by: 60)
        let (minutes, overflowMinutes) = hours.addingReportingOverflow(minutesField.integerValue)
        let text = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !overflowHours, !overflowMinutes, hoursField.integerValue >= 0, minutesField.integerValue >= 0,
              minutes > 0, !text.isEmpty else {
            validationLabel.stringValue = "Enter a message and an interval greater than zero."
            return
        }
        let hoursEnabled = activeHoursButton.state == .on
        let hoursWindow = ActiveHours(startMinute: time(on: startPicker), endMinute: time(on: endPicker))
        if hoursEnabled {
            guard hoursWindow.isValid else {
                validationLabel.stringValue = "Start and end must differ. Turn off Active Hours for all-day reminders."
                return
            }
            guard TimeInterval(minutes) * 60 + TimeInterval(lockSeconds) <= hoursWindow.duration else {
                validationLabel.stringValue = "Allow more time than the reminder interval (plus 3 seconds), or shorten the interval."
                return
            }
        }
        defaults.set(text, forKey: kText)
        defaults.set(minutes, forKey: kMinutes)
        defaults.set(hoursEnabled, forKey: kActiveHours)
        defaults.set(hoursWindow.startMinute, forKey: kActiveStart)
        defaults.set(hoursWindow.endMinute, forKey: kActiveEnd)
        settings?.close()
        schedule()
    }

    private func time(on picker: NSDatePicker) -> Int {
        var calendar = Calendar.current
        calendar.timeZone = picker.timeZone ?? .current
        let parts = calendar.dateComponents([.hour, .minute], from: picker.dateValue)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    private func setTime(_ minute: Int, on picker: NSDatePicker) {
        var calendar = Calendar.current
        calendar.timeZone = .current
        picker.timeZone = .current
        // Use a reference date rather than today's potentially nonexistent DST time.
        let day = calendar.date(from: DateComponents(year: 2024, month: 1, day: 15))!
        picker.dateValue = calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day) ?? day
    }

    private func refreshPickerTimeZone() {
        let start = time(on: startPicker)
        let end = time(on: endPicker)
        setTime(start, on: startPicker)
        setTime(end, on: endPicker)
        timeZoneLabel.stringValue = "Mac time zone: \(TimeZone.autoupdatingCurrent.identifier)"
    }

    @objc private func updateActiveHoursControls() {
        startPicker.isEnabled = activeHoursButton.state == .on
        endPicker.isEnabled = activeHoursButton.state == .on
        timeZoneLabel.stringValue = "Mac time zone: \(TimeZone.autoupdatingCurrent.identifier)"
        validationLabel.stringValue = ""
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
