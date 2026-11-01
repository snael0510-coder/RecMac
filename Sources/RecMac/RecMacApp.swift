import SwiftUI
import AppKit
import Combine

@main
struct RecMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // ⌘, 로 여는 설정 (단축키)
        Settings {
            SettingsView()
                .environmentObject(appDelegate.shortcuts)
        }
    }
}

/// 맥 스크린샷 툴바처럼 떠 있는 패널
final class ToolbarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// 확정된 C-4 로고를 메뉴 막대 크기로 그린다.
private enum StatusLogo {
    static func image(recording: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.scaleBy(x: 0.18, y: 0.18)
            let radii: [CGFloat] = [
                6.02, 6.80, 6.10, 4.49, 3.30, 3.51, 4.95, 6.43, 6.73, 5.60,
                3.98, 3.20, 3.90, 5.51, 6.70, 6.49, 5.05, 3.57, 3.27, 4.40
            ]
            let outerColor = recording ? NSColor.labelColor : NSColor.black
            context.setFillColor(outerColor.cgColor)
            for (index, radius) in radii.enumerated() {
                let angle = CGFloat(index) * .pi / 10 - .pi / 2
                let x = 50 + 38 * cos(angle)
                let y = 50 + 38 * sin(angle)
                context.fillEllipse(in: CGRect(x: x - radius, y: y - radius,
                                               width: radius * 2, height: radius * 2))
            }
            context.setFillColor((recording ? NSColor.systemRed : NSColor.black).cgColor)
            context.fillEllipse(in: CGRect(x: 33, y: 33, width: 34, height: 34))
            return true
        }
        image.isTemplate = !recording
        image.accessibilityDescription = "RecMac"
        return image
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let recorder = Recorder()
    let shortcuts = ShortcutStore()
    private var toolbar: ToolbarPanel?
    private var settingsWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        let size = toolbarSize()
        let panel = ToolbarPanel(contentRect: NSRect(origin: .zero, size: size),
                                 styleMask: [.borderless, .fullSizeContentView],
                                 backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false   // 항상 가운데 아래
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)  // 어둡게 덮는 표시보다 위
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        toolbar = panel
        recorder.mainWindow = panel
        panel.contentView = hosting(ToolbarView().environmentObject(recorder))

        // 화면 아래쪽 가운데 (스크린샷 툴바 자리)
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.minY + 24))
        }
        panel.alphaValue = 0            // 처음엔 숨겨 두었다가 아래에서 스윽 올라오게
        panel.orderFrontRegardless()
        recorder.openSettings = { [weak self] in self?.showSettings() }
        recorder.statusItemFrame = { [weak self] in self?.statusItem?.button?.window?.frame }

        shortcuts.onAction = { [weak self] action in self?.recorder.perform(action) }
        shortcuts.registerAll()

        setupStatusItem()

        recorder.$showAdvanced
            .receive(on: RunLoop.main)
            .dropFirst()
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.resizeToolbar() }
            }
            .store(in: &cancellables)
        recorder.$notice
            .receive(on: RunLoop.main)
            .dropFirst()
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.resizeToolbar() }
            }
            .store(in: &cancellables)

        // 툴바가 앞에 있을 때 ESC → 선택 해제 (한 번 더 누르면 툴바 접기)
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            return MainActor.assumeIsolated {
                guard let self, let panel = self.toolbar, NSApp.keyWindow === panel else { return event }
                self.recorder.handleEscape()
                return nil
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                let before = self.recorder.introTick
                self.recorder.openToolbar()
                if self.recorder.introTick == before { self.recorder.introTick += 1 }   // 첫 실행엔 꼭 한 바퀴
            }
        }
    }

    /// 투명 패널이 실제 바보다 넓으면 뒤의 앱을 클릭할 수 없으므로 상태별 최소 크기만 쓴다.
    private func toolbarSize() -> CGSize {
        CGSize(width: recorder.showAdvanced || recorder.notice != nil ? 910 : 620,
               height: recorder.notice == nil ? 120 : 170)
    }

    private func resizeToolbar() {
        guard let panel = toolbar else { return }
        let size = toolbarSize()
        let old = panel.frame
        guard abs(old.width - size.width) > 1 || abs(old.height - size.height) > 1 else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens[0]
        let origin = NSPoint(x: (screen.visibleFrame.midX - size.width / 2).rounded(),
                             y: screen.visibleFrame.minY + 8)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    // MARK: - 메뉴 막대 아이콘 (언제든 불러오기)

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = StatusLogo.image(recording: false)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item

        // 녹화 중에는 아이콘을 빨간 점으로
        recorder.$isRecording
            .receive(on: RunLoop.main)
            .sink { [weak self] recording in
                MainActor.assumeIsolated {
                    guard let button = self?.statusItem?.button else { return }
                    button.image = StatusLogo.image(recording: recording)
                    button.contentTintColor = nil
                }
            }
            .store(in: &cancellables)
    }

    private func addItem(_ menu: NSMenu, _ title: String, _ action: Selector, shortcut: HotKeyAction? = nil) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        if let shortcut, let s = shortcuts.shortcuts[shortcut] {
            let name = Shortcut.keyName(s.keyCode)
            if name.count == 1 {
                item.keyEquivalent = name.lowercased()
                item.keyEquivalentModifierMask = s.flags.intersection([.command, .option, .control, .shift])
            }
        }
        menu.addItem(item)
    }

    @objc private func menuShowToolbar() { recorder.openToolbar() }
    @objc private func menuToggle() { Task { await recorder.toggle() } }
    @objc private func menuArea() { recorder.perform(.area) }
    @objc private func menuWindow() { recorder.perform(.window) }
    @objc private func menuDisplay() { recorder.perform(.display) }
    @objc private func menuAudio() { recorder.chooseAudio(); Task { await recorder.toggle() } }
    @objc private func menuFolder() { recorder.openFolder() }
    @objc private func menuTrim() { recorder.chooseFileToTrim() }
    @objc private func menuSettings() { showSettings() }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        recorder.openToolbar()
        return true
    }

    /// 녹화 중에 종료하면 파일이 깨지지 않도록 먼저 저장을 마친다
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard recorder.isRecording else { return .terminateNow }
        Task { @MainActor in
            await recorder.stop()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    // 툴바를 숨겨도 앱이 꺼지지 않게 한다
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if recorder.isRecording {
            addItem(menu, tr("녹화 정지", "Stop recording"), #selector(menuToggle), shortcut: .toggle)
        } else {
            addItem(menu, tr("툴바 열기", "Show toolbar"), #selector(menuShowToolbar), shortcut: .showToolbar)
            menu.addItem(.separator())
            addItem(menu, tr("선택 영역 녹화", "Record selection"), #selector(menuArea), shortcut: .area)
            addItem(menu, tr("창 녹화", "Record window"), #selector(menuWindow), shortcut: .window)
            addItem(menu, tr("전체 화면 녹화", "Record full screen"), #selector(menuDisplay), shortcut: .display)
            addItem(menu, tr("오디오만 녹음", "Record audio only"), #selector(menuAudio))
        }
        menu.addItem(.separator())
        addItem(menu, tr("앞뒤 자르기…", "Trim a recording…"), #selector(menuTrim))
        addItem(menu, tr("저장 폴더 열기", "Open folder"), #selector(menuFolder))
        addItem(menu, tr("단축키 설정…", "Shortcuts…"), #selector(menuSettings))
        menu.addItem(.separator())
        addItem(menu, tr("RecMac 종료", "Quit RecMac"), #selector(menuQuit))
    }

    func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
                                  styleMask: [.titled, .closable],
                                  backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        // 열 때마다 새로 그려서 바꾼 언어가 바로 반영되게
        settingsWindow?.title = tr("RecMac 설정", "RecMac Settings")
        settingsWindow?.contentView = NSHostingView(rootView: SettingsView().environmentObject(shortcuts))
        settingsWindow?.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
