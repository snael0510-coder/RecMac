import SwiftUI
import AppKit
import Carbon

enum HotKeyAction: String, CaseIterable, Identifiable, Codable {
    case showToolbar, toggle, area, window, display
    var id: String { rawValue }

    var title: String {
        switch self {
        case .showToolbar: return tr("툴바 열기 / 접기", "Show / hide toolbar")
        case .toggle: return tr("녹화 시작 / 정지", "Start / stop recording")
        case .area: return tr("선택 영역 녹화", "Record selection")
        case .window: return tr("창 녹화", "Record window")
        case .display: return tr("전체 화면 녹화", "Record full screen")
        }
    }

    var detail: String {
        switch self {
        case .showToolbar: return tr("언제든 툴바를 불러와요", "Bring up the toolbar anytime")
        case .toggle: return tr("지금 고른 방식으로 바로 녹화해요", "Records with the current mode")
        case .area: return tr("영역을 드래그하면 바로 녹화해요", "Drag an area, then recording starts")
        case .window: return tr("창을 클릭하면 바로 녹화해요", "Click a window, then recording starts")
        case .display: return tr("화면 전체를 바로 녹화해요", "Records the whole screen right away")
        }
    }

    var hotKeyID: UInt32 {
        switch self {
        case .showToolbar: return 5
        case .toggle: return 1
        case .area: return 2
        case .window: return 3
        case .display: return 4
        }
    }
}

struct Shortcut: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: UInt          // NSEvent.ModifierFlags.rawValue

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    var display: String {
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option) { s += "⌥" }
        if flags.contains(.shift) { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        return s + Self.keyName(keyCode)
    }

    var carbonModifiers: UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        return m
    }

    /// 한글 입력 중이어도 영문 키 이름이 나오도록 키 위치로 이름을 정한다
    static func keyName(_ code: UInt16) -> String {
        let table: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
            11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2",
            20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8",
            29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L", 38: "J",
            39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".",
            50: "`", 49: "Space", 36: "↩", 48: "⇥",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
            101: "F9", 109: "F10", 103: "F11", 111: "F12",
            123: "←", 124: "→", 125: "↓", 126: "↑",
        ]
        return table[code] ?? "#\(code)"
    }

    static let defaultMods = NSEvent.ModifierFlags([.control, .option, .command]).rawValue
    static let defaults: [HotKeyAction: Shortcut] = [
        .showToolbar: Shortcut(keyCode: 17, modifiers: defaultMods), // ⌃⌥⌘T
        .toggle: Shortcut(keyCode: 15, modifiers: defaultMods),   // ⌃⌥⌘R
        .area: Shortcut(keyCode: 0, modifiers: defaultMods),      // ⌃⌥⌘A
        .window: Shortcut(keyCode: 13, modifiers: defaultMods),   // ⌃⌥⌘W
        .display: Shortcut(keyCode: 3, modifiers: defaultMods),   // ⌃⌥⌘F
    ]
}

/// Carbon 전역 단축키 (손쉬운 사용 권한 없이 다른 앱을 쓰는 중에도 동작)
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var handlers: [UInt32: () -> Void] = [:]
    private var installed = false

    func register(id: UInt32, keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        installIfNeeded()
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4D52_4543), id: id)   // 'MREC'
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref {
            refs[id] = ref
            handlers[id] = handler
        }
    }

    func unregister(id: UInt32) {
        if let ref = refs[id] { UnregisterEventHotKey(ref) }
        refs[id] = nil
        handlers[id] = nil
    }

    /// 영역/창 고르는 동안만 ESC를 전역으로 잡는다
    static let escapeID: UInt32 = 90
    func captureEscape(_ handler: @escaping () -> Void) {
        unregister(id: Self.escapeID)
        register(id: Self.escapeID, keyCode: 53, modifiers: 0, handler: handler)
    }
    func releaseEscape() {
        unregister(id: Self.escapeID)
    }

    func unregisterAll() {
        for ref in refs.values { UnregisterEventHotKey(ref) }
        refs.removeAll()
        handlers.removeAll()
    }

    fileprivate func fire(_ id: UInt32) {
        handlers[id]?()
    }

    private func installIfNeeded() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let id = hotKeyID.id
            DispatchQueue.main.async {
                MainActor.assumeIsolated { HotKeyCenter.shared.fire(id) }
            }
            return noErr
        }, 1, &spec, nil, nil)
    }
}

@MainActor
final class ShortcutStore: ObservableObject {
    @Published private(set) var shortcuts: [HotKeyAction: Shortcut] = [:]
    var onAction: (HotKeyAction) -> Void = { _ in }
    private var suspended = false

    private let storageKey = "shortcuts"
    private let customizedKey = "shortcutsCustomized"

    init() {
        let d = UserDefaults.standard
        if d.bool(forKey: customizedKey),
           let data = d.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([String: Shortcut].self, from: data) {
            var map: [HotKeyAction: Shortcut] = [:]
            for (k, v) in saved { if let a = HotKeyAction(rawValue: k) { map[a] = v } }
            // 나중에 추가된 기능은 기본 단축키를 한 번 채워 준다
            if !d.bool(forKey: "shortcutShowToolbarSeeded") {
                if map[.showToolbar] == nil, let def = Shortcut.defaults[.showToolbar],
                   !map.values.contains(def) { map[.showToolbar] = def }
                d.set(true, forKey: "shortcutShowToolbarSeeded")
            }
            shortcuts = map
        } else {
            shortcuts = Shortcut.defaults
        }
    }

    func set(_ shortcut: Shortcut?, for action: HotKeyAction) {
        if let shortcut {
            // 같은 단축키가 다른 기능에 있으면 거기서는 뺀다
            for (a, s) in shortcuts where s == shortcut && a != action { shortcuts[a] = nil }
        }
        shortcuts[action] = shortcut
        save()
        if !suspended { registerAll() }
    }

    func resetDefaults() {
        shortcuts = Shortcut.defaults
        save()
        if !suspended { registerAll() }
    }

    func registerAll() {
        HotKeyCenter.shared.unregisterAll()
        for (action, s) in shortcuts {
            HotKeyCenter.shared.register(id: action.hotKeyID, keyCode: UInt32(s.keyCode),
                                         modifiers: s.carbonModifiers) { [weak self] in
                self?.onAction(action)
            }
        }
    }

    /// 단축키를 새로 입력받는 동안에는 잠시 꺼 둔다
    func suspend() {
        suspended = true
        HotKeyCenter.shared.unregisterAll()
    }

    func resume() {
        suspended = false
        registerAll()
    }

    private func save() {
        var map: [String: Shortcut] = [:]
        for (a, s) in shortcuts { map[a.rawValue] = s }
        let d = UserDefaults.standard
        d.set(try? JSONEncoder().encode(map), forKey: storageKey)
        d.set(true, forKey: customizedKey)
    }
}

// MARK: - 설정 화면

struct SettingsView: View {
    @EnvironmentObject var shortcuts: ShortcutStore

    var body: some View {
        Form {
            Section {
                ForEach(HotKeyAction.allCases) { action in
                    LabeledContent {
                        ShortcutField(action: action)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(action.title)
                            Text(action.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text(tr("전역 단축키", "Global shortcuts"))
            } footer: {
                Text(tr("다른 앱을 쓰는 중에도 작동해요. 칸을 누르고 원하는 키를 누르세요. ⌘ ⌥ ⌃ 중 하나는 꼭 들어가야 하고, ⌫는 지우기, esc는 취소예요.", "Works while you use other apps. Click a field and press keys. Include ⌘, ⌥ or ⌃. ⌫ clears, esc cancels."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Spacer()
                    Button(tr("기본값으로 되돌리기", "Restore defaults")) { shortcuts.resetDefaults() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
    }
}

private struct ShortcutField: View {
    let action: HotKeyAction
    @EnvironmentObject var shortcuts: ShortcutStore
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button {
                recording ? stop() : start()
            } label: {
                Text(recording ? tr("키를 누르세요…", "Press keys…") : (shortcuts.shortcuts[action]?.display ?? tr("없음", "None")))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(recording ? Color.primary : (shortcuts.shortcuts[action] == nil ? Color.secondary : Color.primary))
                    .frame(minWidth: 116)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 10)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(recording ? Color.primary.opacity(0.14) : Color.primary.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(recording ? Color.primary.opacity(0.5) : Color.primary.opacity(0.12)))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                shortcuts.set(nil, for: action)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(shortcuts.shortcuts[action] != nil && !recording ? 1 : 0)
            .help(tr("지우기", "Clear"))
        }
        .animation(.easeInOut(duration: 0.15), value: recording)
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        shortcuts.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated { handle(event) }
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        if event.keyCode == 53 {                       // esc: 취소
            stop()
            return nil
        }
        if event.keyCode == 51 || event.keyCode == 117 { // ⌫: 지우기
            shortcuts.set(nil, for: action)
            stop()
            return nil
        }
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !mods.intersection([.command, .option, .control]).isEmpty else {
            NSSound.beep()
            return nil
        }
        shortcuts.set(Shortcut(keyCode: event.keyCode, modifiers: mods.rawValue), for: action)
        stop()
        return nil
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording {
            recording = false
            shortcuts.resume()
        }
    }
}
