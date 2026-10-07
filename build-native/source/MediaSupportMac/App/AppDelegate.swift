import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private weak var speechModelMenu: NSMenu?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        configureMainMenu()
        AppCoordinator.shared.bootstrap()
        MainWindowController.shared.show()
        scheduleLayoutCaptureIfNeeded()
    }

    private func scheduleLayoutCaptureIfNeeded() {
        guard ProcessInfo.processInfo.environment["MSM_CAPTURE_LAYOUT"] == "1" else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let store = BurnPanelAnchorStore.shared
            let supportDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/Media Support Master", isDirectory: true)
            try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
            let anchorLine =
                "burn leftX=\(store.leftX) bottomY=\(store.bottomY) width=\(store.panelWidth) " +
                "buttonCenterX=\(store.burnButtonCenterX)\n"
            try? anchorLine.write(
                to: supportDir.appendingPathComponent("panel-anchor.txt"),
                atomically: true,
                encoding: .utf8
            )
            if let preset = SystemPanelLayoutStore.captureFromCurrentPanels(),
               let data = try? JSONEncoder().encode(preset) {
                try? data.write(to: supportDir.appendingPathComponent("panel-layout.json"))
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        AppShutdown.perform()
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppShutdown.perform()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            MainWindowController.shared.show()
        }
        return true
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        let aboutItem = appMenu.addItem(
            withTitle: L10n.string("Về Media Support Master"),
            action: #selector(openAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        let settingsItem = appMenu.addItem(
            withTitle: L10n.string("Cài đặt…"),
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        let shortcutsItem = appMenu.addItem(
            withTitle: L10n.string("Phím tắt Timeline…"),
            action: #selector(openTimelineShortcuts),
            keyEquivalent: ""
        )
        shortcutsItem.target = self
        appMenu.addItem(.separator())
        let savePanelLayoutItem = appMenu.addItem(
            withTitle: L10n.string("Lưu vị trí panel màu/font"),
            action: #selector(saveSystemPanelLayout),
            keyEquivalent: ""
        )
        savePanelLayoutItem.target = self
        appMenu.addItem(.separator())
        let checkItem = appMenu.addItem(
            withTitle: L10n.string("Kiểm tra engine"),
            action: #selector(runEngineCheck),
            keyEquivalent: "k"
        )
        checkItem.target = self
        appMenu.addItem(.separator())
        let quitItem = appMenu.addItem(
            withTitle: L10n.string("Thoát Media Support Master"),
            action: #selector(quitApplication(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = self

        let subtitleMenuItem = NSMenuItem(title: L10n.string("Phụ đề"), action: nil, keyEquivalent: "")
        let subtitleMenu = NSMenu(title: L10n.string("Phụ đề"))
        subtitleMenuItem.submenu = subtitleMenu
        mainMenu.addItem(subtitleMenuItem)

        let automaticSubtitleItem = subtitleMenu.addItem(
            withTitle: L10n.string("Tạo sub tự động"),
            action: #selector(openAutomaticSubtitles),
            keyEquivalent: "1"
        )
        automaticSubtitleItem.keyEquivalentModifierMask = [.command]
        automaticSubtitleItem.target = self
        let scriptSubtitleItem = subtitleMenu.addItem(
            withTitle: L10n.string("Khớp văn bản gốc"),
            action: #selector(openScriptSubtitles),
            keyEquivalent: "2"
        )
        scriptSubtitleItem.keyEquivalentModifierMask = [.command]
        scriptSubtitleItem.target = self
        subtitleMenu.addItem(.separator())

        let speechModelItem = NSMenuItem(title: L10n.string("Model chép lời"), action: nil, keyEquivalent: "")
        let speechModelMenu = NSMenu(title: L10n.string("Model chép lời"))
        speechModelMenu.delegate = self
        speechModelItem.submenu = speechModelMenu
        subtitleMenu.addItem(speechModelItem)
        self.speechModelMenu = speechModelMenu
        refreshSpeechModelMenu()

        // Edit — bắt buộc để Cmd+C/V/X/A/Z tới NSTextView / TextField (First Responder).
        let editMenuItem = NSMenuItem(title: L10n.string("Edit"), action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: L10n.string("Edit"))
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        editMenu.addItem(
            withTitle: L10n.string("Undo"),
            action: Selector(("undo:")),
            keyEquivalent: "z"
        )
        let redoItem = editMenu.addItem(
            withTitle: L10n.string("Redo"),
            action: Selector(("redo:")),
            keyEquivalent: "z"
        )
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(
            withTitle: L10n.string("Cut"),
            action: #selector(NSText.cut(_:)),
            keyEquivalent: "x"
        )
        editMenu.addItem(
            withTitle: L10n.string("Copy"),
            action: #selector(NSText.copy(_:)),
            keyEquivalent: "c"
        )
        editMenu.addItem(
            withTitle: L10n.string("Paste"),
            action: #selector(NSText.paste(_:)),
            keyEquivalent: "v"
        )
        editMenu.addItem(
            withTitle: L10n.string("Paste and Match Style"),
            action: #selector(NSTextView.pasteAsPlainText(_:)),
            keyEquivalent: "v"
        ).keyEquivalentModifierMask = [.command, .option, .shift]
        editMenu.addItem(
            withTitle: L10n.string("Delete"),
            action: #selector(NSText.delete(_:)),
            keyEquivalent: ""
        )
        editMenu.addItem(
            withTitle: L10n.string("Select All"),
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )

        let windowMenuItem = NSMenuItem(title: L10n.string("Window"), action: nil, keyEquivalent: "")
        let windowMenu = NSMenu(title: L10n.string("Window"))
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        NSApp.windowsMenu = windowMenu

        windowMenu.addItem(
            withTitle: L10n.string("Thu nhỏ"),
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        )
        windowMenu.addItem(
            withTitle: L10n.string("Zoom"),
            action: #selector(NSWindow.performZoom(_:)),
            keyEquivalent: ""
        )
        windowMenu.addItem(.separator())
        windowMenu.addItem(
            withTitle: L10n.string("Bring All to Front"),
            action: #selector(NSApplication.arrangeInFront(_:)),
            keyEquivalent: ""
        )

        NSApp.mainMenu = mainMenu
    }

    func menuWillOpen(_ menu: NSMenu) {
        if menu === speechModelMenu {
            refreshSpeechModelMenu()
        }
    }

    private func refreshSpeechModelMenu() {
        guard let speechModelMenu else { return }
        speechModelMenu.removeAllItems()
        let selectedModel = GroqModelPreferences.selectedSpeechModel
        for model in GroqSpeechModel.allCases {
            let item = speechModelMenu.addItem(
                withTitle: L10n.string(model.menuLabel),
                action: #selector(selectSpeechModel(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = model.rawValue
            item.state = model == selectedModel ? .on : .off
            item.toolTip = L10n.string(model.detail)
        }
    }

    @objc private func openSettings() {
        AppCoordinator.shared.openSettings()
    }

    @objc private func openTimelineShortcuts() {
        NotificationCenter.default.post(name: .openTimelineShortcutSettings, object: nil)
    }

    @objc private func openAutomaticSubtitles() {
        AppCoordinator.shared.openMainWindow(section: .subtitleCreate)
    }

    @objc private func openScriptSubtitles() {
        AppCoordinator.shared.openMainWindow(section: .subtitleScript)
    }

    @objc private func selectSpeechModel(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              GroqSpeechModel(rawValue: rawValue) != nil else { return }
        UserDefaults.standard.set(rawValue, forKey: GroqModelPreferences.speechModelKey)
        refreshSpeechModelMenu()
    }

    @objc private func runEngineCheck() {
        AppCoordinator.shared.runCheckEngines()
    }

    @objc private func saveSystemPanelLayout() {
        _ = SystemPanelLayoutStore.captureFromCurrentPanels()
    }

    @objc private func openAbout() {
        AppCoordinator.shared.openSettings(tab: .about)
    }

    @objc private func quitApplication(_ sender: Any?) {
        AppShutdown.perform()
        NSApp.terminate(sender)
    }
}
