import Foundation
import AppKit
import SwiftUI
import AVFoundation
import CoreMedia
import ScreenCaptureKit
import UniformTypeIdentifiers

enum CaptureMode: String, CaseIterable, Identifiable {
    case area, display, window, audio
    var id: String { rawValue }

    var title: String {
        switch self {
        case .area: return tr("선택 영역", "Selection")
        case .display: return tr("전체 화면", "Full Screen")
        case .window: return tr("창", "Window")
        case .audio: return tr("오디오", "Audio")
        }
    }

    var icon: String {
        switch self {
        case .area: return "rectangle.dashed"
        case .display: return "display"
        case .window: return "macwindow"
        case .audio: return "waveform"
        }
    }

    var isVideo: Bool { self != .audio }
}

enum OutputQuality: String, CaseIterable, Identifiable {
    case original, p1080, p720
    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: return tr("원본", "Original")
        case .p1080: return "1080p"
        case .p720: return "720p"
        }
    }

    var maxHeight: CGFloat? {
        switch self {
        case .original: return nil
        case .p1080: return 1080
        case .p720: return 720
        }
    }
}

/// 영상 파일 형식 (녹화 엔진이 기본으로 지원하는 조합만)
enum VideoFormat: String, CaseIterable, Identifiable {
    case mp4H264, mp4HEVC, movH264
    var id: String { rawValue }

    var title: String {
        switch self {
        case .mp4H264: return tr("MP4 · H.264 (어디서나 재생)", "MP4 · H.264 (plays anywhere)")
        case .mp4HEVC: return tr("MP4 · HEVC (용량 절반)", "MP4 · HEVC (half the size)")
        case .movH264: return tr("MOV · H.264 (Final Cut·iMovie)", "MOV · H.264 (Final Cut, iMovie)")
        }
    }

    var short: String {
        switch self {
        case .mp4H264: return "MP4"
        case .mp4HEVC: return "HEVC"
        case .movH264: return "MOV"
        }
    }

    var fileType: AVFileType { self == .movH264 ? .mov : .mp4 }
    var codec: AVVideoCodecType { self == .mp4HEVC ? .hevc : .h264 }
    var fileExtension: String { self == .movH264 ? "mov" : "mp4" }
}

enum RecorderError: LocalizedError {
    case noMode, noDisplay, noWindow, noArea, noAudioSource, microphoneDenied, exportFailed

    var errorDescription: String? {
        switch self {
        case .noMode: return tr("녹화 방식을 먼저 골라 주세요.", "Choose what to record first.")
        case .noDisplay: return tr("녹화할 디스플레이를 찾지 못했어요.", "Couldn't find a display to record.")
        case .noWindow: return tr("녹화할 창을 찾지 못했어요. 창을 다시 골라 주세요.", "Couldn't find that window. Please pick it again.")
        case .noArea: return tr("녹화할 영역을 먼저 선택해 주세요.", "Select an area first.")
        case .noAudioSource: return tr("내부 소리나 마이크 중 하나는 켜 주세요.", "Turn on system audio or the microphone.")
        case .microphoneDenied: return tr("마이크 권한이 없어요. 시스템 설정 > 개인정보 보호 및 보안 > 마이크에서 허용해 주세요.", "Microphone access is off. Allow it in System Settings > Privacy & Security > Microphone.")
        case .exportFailed: return tr("오디오 파일을 만들지 못했어요.", "Couldn't create the audio file.")
        }
    }
}

/// 창 위에 잠깐 떴다 사라지는 알림
struct Notice: Equatable {
    let id = UUID()
    let text: String
    let isError: Bool
    var fileURL: URL? = nil
}

/// 화면/창/선택 영역 + 소리를 .mp4로, 또는 소리만 .m4a로 녹화한다.
@MainActor
final class Recorder: NSObject, ObservableObject {
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let showCursor = "showCursor"
        static let quality = "quality"
        static let fps = "fps"
        static let format = "videoFormat"
        static let systemAudio = "includeSystemAudio"
        static let microphone = "includeMicrophone"
        static let countdown = "countdownEnabled"
        static let sounds = "playSounds"
        static let hideWindow = "hideWindowWhileRecording"
        static let advanced = "showAdvanced"
    }

    // MARK: 녹화 대상 (nil = 아직 고르지 않음)
    @Published var mode: CaptureMode? = nil {
        didSet { updateHighlight() }
    }
    @Published var displays: [SCDisplay] = []
    @Published var selectedDisplayID: CGDirectDisplayID = CGMainDisplayID() {
        didSet {
            if oldValue != selectedDisplayID { area = nil }
            updateHighlight()
        }
    }
    @Published var windows: [SCWindow] = []
    @Published var selectedWindowID: CGWindowID? {
        didSet { updateHighlight() }
    }
    @Published var area: CGRect? {        // 디스플레이 기준 좌표(포인트, 왼쪽 위 원점)
        didSet { updateHighlight() }
    }

    // MARK: 옵션 (앱을 껐다 켜도 유지)
    @Published var showCursor: Bool { didSet { defaults.set(showCursor, forKey: Keys.showCursor) } }
    @Published var quality: OutputQuality { didSet { defaults.set(quality.rawValue, forKey: Keys.quality) } }
    @Published var fps: Int { didSet { defaults.set(fps, forKey: Keys.fps) } }
    @Published var videoFormat: VideoFormat { didSet { defaults.set(videoFormat.rawValue, forKey: Keys.format) } }
    @Published var includeSystemAudio: Bool { didSet { defaults.set(includeSystemAudio, forKey: Keys.systemAudio) } }
    @Published var includeMicrophone: Bool { didSet { defaults.set(includeMicrophone, forKey: Keys.microphone) } }
    @Published var countdownEnabled: Bool { didSet { defaults.set(countdownEnabled, forKey: Keys.countdown) } }
    @Published var playSounds: Bool { didSet { defaults.set(playSounds, forKey: Keys.sounds) } }
    @Published var hideWindowWhileRecording: Bool { didSet { defaults.set(hideWindowWhileRecording, forKey: Keys.hideWindow) } }
    @Published var showAdvanced: Bool { didSet { defaults.set(showAdvanced, forKey: Keys.advanced) } }
    @Published var language: AppLanguage = AppLanguage.current {
        didSet { defaults.set(language.rawValue, forKey: AppLanguage.storageKey) }
    }

    // MARK: 상태
    @Published var isRecording = false {
        didSet { updateHighlight() }
    }
    @Published var isBusy = false
    @Published var countdownActive = false
    @Published var elapsedText = "00:00"
    @Published var lastFileURL: URL? {
        didSet { defaults.set(lastFileURL?.path, forKey: "lastFilePath") }
    }
    @Published var notice: Notice?
    @Published var flyTick = 0              // 늘어날 때마다 툴바가 메뉴 막대로 빨려 올라가는 모션
    @Published var introTick = 0            // 늘어날 때마다 툴바 테두리에 빨간 선이 한 바퀴 돈다

    weak var mainWindow: NSWindow?          // 툴바 패널
    var openSettings: () -> Void = {}
    var statusItemFrame: () -> NSRect? = { nil }   // 메뉴 막대 아이콘 위치
    private var isPicking = false
    private var observers: [NSObjectProtocol] = []
    private var restoreToolbarAfterRecording = true

    private var stream: SCStream?
    private var recordingOutput: SCRecordingOutput?
    private var currentFileURL: URL?
    private var pendingAudioURL: URL?        // 오디오 모드: 최종 .m4a 위치
    private var didFinishWriting = false
    private var finishWaiter: CheckedContinuation<Void, Never>?
    private let sink = SampleSink()
    private let sinkQueue = DispatchQueue(label: "RecMac.sink")
    private var timer: Timer?
    private var startDate: Date?
    private var trackTimer: Timer?
    private var trackedSourceRect: CGRect?
    private let areaSelector = AreaSelector()
    private let windowPicker = WindowPicker()
    private let highlight = HighlightOverlay()
    private let countdown = CountdownOverlay()
    private let island = Island()
    private let trimmer = TrimController()

    override init() {
        let d = UserDefaults.standard
        d.register(defaults: [
            Keys.showCursor: true,
            Keys.quality: OutputQuality.original.rawValue,
            Keys.fps: 60,
            Keys.format: VideoFormat.mp4H264.rawValue,
            Keys.systemAudio: true,      // 기본: 맥 내부 소리 녹음
            Keys.microphone: false,
            Keys.countdown: true,        // 기본: 3초 카운트다운
            Keys.sounds: true,
            Keys.hideWindow: true,
            Keys.advanced: false,        // 기본: 고급 옵션 접어 두기
        ])
        showCursor = d.bool(forKey: Keys.showCursor)
        quality = OutputQuality(rawValue: d.string(forKey: Keys.quality) ?? "") ?? .original
        fps = d.integer(forKey: Keys.fps) == 30 ? 30 : 60
        videoFormat = VideoFormat(rawValue: d.string(forKey: Keys.format) ?? "") ?? .mp4H264
        includeSystemAudio = d.bool(forKey: Keys.systemAudio)
        includeMicrophone = d.bool(forKey: Keys.microphone)
        countdownEnabled = d.bool(forKey: Keys.countdown)
        playSounds = d.bool(forKey: Keys.sounds)
        hideWindowWhileRecording = d.bool(forKey: Keys.hideWindow)
        showAdvanced = d.bool(forKey: Keys.advanced)
        super.init()

        if let path = d.string(forKey: "lastFilePath"), FileManager.default.fileExists(atPath: path) {
            lastFileURL = URL(fileURLWithPath: path)
        }

        // 툴바는 사용자가 직접 접을 때만 사라진다.
        // 데스크탑을 넘기거나 모니터 구성이 바뀌면 지금 보고 있는 화면의 가운데 아래로 따라간다.
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.repositionToolbar() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.repositionToolbar() }
        })
    }

    // MARK: - 툴바 ↔ 노치 아일랜드

    /// 툴바를 숨긴다. 메뉴 막대 아이콘, 단축키, Dock 아이콘으로 다시 부른다.
    /// 노치 아일랜드는 녹화 중에만 나타난다.
    func collapseToIsland() {
        hideMainWindow(toMenuBar: true)
        if !isRecording {
            island.hide()
            highlight.hide()      // 툴바 없이 화면만 어두운 상태로 남지 않게
        }
    }

    /// 툴바를 다시 펼친다 (아래에서 스윽 올라오고 테두리에 빨간 선이 한 바퀴)
    func openToolbar() {
        if !isRecording { island.hide() }
        let wasHidden = !isToolbarVisible
        showMainWindow()
        updateHighlight()
        if wasHidden { introTick += 1 }
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    var isToolbarVisible: Bool {
        guard let w = mainWindow else { return false }
        return w.isVisible && w.alphaValue > 0.5 && !w.ignoresMouseEvents
    }

    // MARK: - 전역 단축키

    func perform(_ action: HotKeyAction) {
        if action == .showToolbar {
            // 언제든 툴바 열기/접기 (녹화 중이면 아일랜드 그대로)
            if isRecording { return }
            if isToolbarVisible && NSApp.isActive { collapseToIsland() } else { openToolbar() }
            return
        }
        if isRecording {
            Task { await stop() }
            return
        }
        guard !isBusy, !countdownActive, !isPicking else { return }
        switch action {
        case .toggle:
            Task { await toggle() }
        case .area:
            Task {
                await chooseArea(bringBack: false)
                if mode == .area { await toggle() }
            }
        case .window:
            Task {
                await chooseWindow(bringBack: false)
                if mode == .window { await toggle() }
            }
        case .display:
            chooseDisplay()
            Task { await toggle() }
        case .showToolbar:
            break
        }
    }

    // MARK: - 알림

    func post(_ text: String, isError: Bool = false, fileURL: URL? = nil) {
        let n = Notice(text: text, isError: isError, fileURL: fileURL)
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { notice = n }
        DispatchQueue.main.asyncAfter(deadline: .now() + (isError ? 6 : 4)) { [weak self] in
            MainActor.assumeIsolated {
                if self?.notice?.id == n.id { self?.dismissNotice() }
            }
        }
    }

    func dismissNotice() {
        withAnimation(.easeInOut(duration: 0.35)) { notice = nil }
    }

    // MARK: - 대상 목록

    func refreshContent() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            let myPID = ProcessInfo.processInfo.processIdentifier

            displays = content.displays
            if !displays.contains(where: { $0.displayID == selectedDisplayID }) {
                selectedDisplayID = displays.first?.displayID ?? CGMainDisplayID()
            }

            windows = content.windows
                .filter { w in
                    w.windowLayer == 0 && w.isOnScreen
                        && w.frame.width > 80 && w.frame.height > 60
                        && w.owningApplication?.processID != myPID
                }
        } catch {
            post(describe(error), isError: true)
        }
    }

    func label(for display: SCDisplay) -> String {
        let name = Self.screen(for: display.displayID)?.localizedName ?? tr("디스플레이", "Display")
        return "\(name) (\(display.width)×\(display.height))"
    }

    /// 창 모드는 그 앱의 소리만 담기므로 설명도 그에 맞게
    var systemAudioTip: String {
        mode == .window ? tr("이 앱의 소리 포함", "Include this app's sound")
                        : tr("내부 소리 포함", "Include system audio")
    }

    /// 방식 버튼에 마우스를 올렸을 때 보여 줄 설명
    func tip(for mode: CaptureMode) -> String {
        switch mode {
        case .display:
            if displays.count > 1, let name = Self.screen(for: selectedDisplayID)?.localizedName {
                return tr("전체 화면 · \(name)", "Full Screen · \(name)")
            }
            return tr("전체 화면", "Full Screen")
        case .window:
            if self.mode == .window, let id = selectedWindowID,
               let app = windows.first(where: { $0.windowID == id })?.owningApplication?.applicationName {
                return tr("창 · \(app)", "Window · \(app)")
            }
            return tr("창 선택", "Pick a window")
        case .area:
            if self.mode == .area, let a = area { return tr("선택 영역 · \(Int(a.width))×\(Int(a.height))", "Selection · \(Int(a.width))×\(Int(a.height))") }
            return tr("선택 영역", "Selection")
        case .audio:
            return tr("오디오만 녹음", "Audio only")
        }
    }

    /// 방금 녹화한 파일의 앞뒤를 잘라 새 파일로 저장
    func trimLastFile() {
        guard let url = lastFileURL else { chooseFileToTrim(); return }
        trim(url)
    }

    /// 아무 영상·오디오 파일이나 골라서 자르기 (기본 위치: 저장 폴더)
    func chooseFileToTrim() {
        let panel = NSOpenPanel()
        panel.title = tr("자를 파일 고르기", "Choose a file to trim")
        panel.prompt = tr("열기", "Open")
        panel.allowedContentTypes = [.movie, .audio]
        panel.allowsMultipleSelection = false
        panel.directoryURL = lastFileURL?.deletingLastPathComponent() ?? (try? outputFolder())
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        trim(url)
    }

    private func trim(_ url: URL) {
        trimmer.open(url: url) { [weak self] result in
            guard let self else { return }
            switch result {
            case .saved(let newURL):
                self.lastFileURL = newURL
                self.post(tr("잘라서 저장했어요 · ", "Trimmed · ") + newURL.lastPathComponent, fileURL: newURL)
            case .failed:
                self.post(tr("자르기에 실패했어요.", "Couldn't trim the file."), isError: true)
            case .cancelled:
                break
            }
        }
    }

    func revealLastFile() {
        guard let url = lastFileURL else { openFolder(); return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openFolder() {
        guard let folder = try? outputFolder() else { return }
        NSWorkspace.shared.open(folder)
    }

    static func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { $0.displayID == displayID }
    }

    // MARK: - 방식 고르기

    /// 툴바에서 ESC: 고른 영역/창을 풀고, 이미 비어 있으면 툴바를 접는다
    func handleEscape() {
        if countdownActive { countdown.cancel(); return }
        guard !isRecording, !isBusy, !isPicking else { return }
        if mode != nil {
            mode = nil
        } else {
            collapseToIsland()
        }
    }

    func chooseDisplay() {
        mode = .display
    }

    func chooseAudio() {
        mode = .audio
    }

    /// 드래그로 영역 고르기. 취소하면 아무 방식도 선택되지 않는다.
    func chooseArea(bringBack: Bool = true) async {
        let mouse = NSEvent.mouseLocation
        if let here = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }),
           here.displayID != selectedDisplayID {
            selectedDisplayID = here.displayID
        }
        guard let screen = Self.screen(for: selectedDisplayID) ?? NSScreen.main else { return }
        highlight.hide()
        isPicking = true
        let rect = await areaSelector.select(on: screen)
        isPicking = false
        if let rect {
            area = rect
            mode = .area
            if bringBack { bringToFront() }
        } else {
            mode = nil
            bringToFront()     // 취소하면 항상 툴바로 돌아온다
        }
    }

    /// 화면에서 창 클릭해서 고르기. 취소하면 아무 방식도 선택되지 않는다.
    func chooseWindow(bringBack: Bool = true) async {
        highlight.hide()
        isPicking = true
        let picked = await windowPicker.pick()
        isPicking = false
        if let id = picked {
            await refreshContent()
            selectedWindowID = id
            mode = .window
            if bringBack { bringToFront() }
        } else {
            mode = nil
            bringToFront()     // 취소하면 항상 툴바로 돌아온다
        }
    }

    /// 녹화 대상의 전역 좌표 영역 (카운트다운 위치용)
    private func targetGlobalRect() -> CGRect? {
        switch mode {
        case .display:
            return CGDisplayBounds(selectedDisplayID)
        case .area:
            guard let area else { return nil }
            let b = CGDisplayBounds(selectedDisplayID)
            return area.offsetBy(dx: b.minX, dy: b.minY)
        case .window:
            guard let id = selectedWindowID else { return nil }
            return WindowList.frame(of: id)
        case .audio, .none:
            return nil
        }
    }

    /// 창/선택 영역 모드에서 대상만 밝게 남기고 나머지를 어둡게 표시
    func updateHighlight() {
        switch mode {
        case .area:
            guard let area else { highlight.hide(); return }
            let bounds = CGDisplayBounds(selectedDisplayID)
            let globalRect = area.offsetBy(dx: bounds.minX, dy: bounds.minY)
            highlight.show(cornerRadius: 0) { globalRect }
        case .window:
            guard let id = selectedWindowID else { highlight.hide(); return }
            highlight.show(cornerRadius: 10) { WindowList.frame(of: id) }
        case .display, .audio, .none:
            highlight.hide()
            return
        }
        highlight.setRecording(isRecording)
    }

    // MARK: - 녹화

    func toggle() async {
        if isRecording {
            await stop()
            return
        }
        guard !isBusy, !countdownActive else { return }
        guard let mode else {
            openToolbar()
            post(RecorderError.noMode.localizedDescription, isError: true)
            return
        }
        if mode == .audio && !includeSystemAudio && !includeMicrophone {
            post(RecorderError.noAudioSource.localizedDescription, isError: true)
            return
        }
        if mode == .area && area == nil {
            await chooseArea()
            guard self.mode == .area else { return }
        }
        if mode == .window && selectedWindowID == nil {
            await chooseWindow()
            guard self.mode == .window else { return }
        }

        restoreToolbarAfterRecording = isToolbarVisible
        if hideWindowWhileRecording {
            hideMainWindow()
        }

        if countdownEnabled {
            countdownActive = true
            HotKeyCenter.shared.captureEscape { [weak self] in self?.countdown.cancel() }
            let finished = await countdown.run(around: targetGlobalRect(), tick: playSounds)
            HotKeyCenter.shared.releaseEscape()
            countdownActive = false
            guard finished else {
                // 취소: 녹화하지 않고 원래 상태로
                if restoreToolbarAfterRecording { showMainWindow() }
                restoreToolbarAfterRecording = true
                return
            }
        }

        await start()
    }

    private func start() async {
        guard let mode else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            if includeMicrophone {
                let granted = await AVCaptureDevice.requestAccess(for: .audio)
                if !granted { throw RecorderError.microphoneDenied }
            }

            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            let myPID = ProcessInfo.processInfo.processIdentifier
            let ownApps = content.applications.filter { $0.processID == myPID }

            let filter: SCContentFilter
            var sourceRect: CGRect?
            var tracking: (windowID: CGWindowID, displayFrame: CGRect)?

            switch mode {
            case .display, .area, .audio:
                guard let display = content.displays.first(where: { $0.displayID == selectedDisplayID })
                        ?? content.displays.first else { throw RecorderError.noDisplay }
                filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
                if mode == .area {
                    guard let area else { throw RecorderError.noArea }
                    sourceRect = area
                }
            case .window:
                // 창 하나만 찍으면 메뉴·드롭다운·대화상자(별도 창)가 빠지므로,
                // 그 앱의 모든 창을 찍되 고른 창 영역만 잘라서 녹화한다.
                guard let id = selectedWindowID,
                      let window = content.windows.first(where: { $0.windowID == id }),
                      let app = window.owningApplication else {
                    throw RecorderError.noWindow
                }
                let frame = WindowList.frame(of: id) ?? window.frame
                let center = CGPoint(x: frame.midX, y: frame.midY)
                guard let display = content.displays.first(where: { $0.frame.contains(center) })
                        ?? content.displays.first else { throw RecorderError.noDisplay }
                filter = SCContentFilter(display: display, including: [app], exceptingWindows: [])
                let local = frame
                    .offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
                    .intersection(CGRect(origin: .zero, size: display.frame.size))
                guard !local.isNull, local.width > 2, local.height > 2 else { throw RecorderError.noWindow }
                sourceRect = local
                tracking = (id, display.frame)
            }

            let config = SCStreamConfiguration()
            if mode.isVideo {
                // 출력 해상도 (레티나 배율 적용, H.264 한계 때문에 긴 변 4096 제한)
                let info = SCShareableContent.info(for: filter)
                let scale = CGFloat(info.pointPixelScale)
                let baseSize = sourceRect?.size ?? info.contentRect.size
                var width = baseSize.width * scale
                var height = baseSize.height * scale
                let maxSide: CGFloat = videoFormat.codec == .h264 ? 4096 : 8192
                if max(width, height) > maxSide {
                    let ratio = maxSide / max(width, height)
                    width *= ratio
                    height *= ratio
                }
                if let maxHeight = quality.maxHeight, height > maxHeight {
                    let ratio = maxHeight / height
                    width *= ratio
                    height *= ratio
                }
                config.width = max(Int(width) & ~1, 2)
                config.height = max(Int(height) & ~1, 2)
                if let sourceRect { config.sourceRect = sourceRect }
                config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
                config.showsCursor = showCursor
            } else {
                // 오디오 모드: 영상은 아주 작게만 받고 나중에 버린다
                config.width = 128
                config.height = 72
                config.minimumFrameInterval = CMTime(value: 1, timescale: 2)
                config.showsCursor = false
            }
            config.queueDepth = 6
            config.ignoreShadowsSingleWindow = true
            config.capturesAudio = includeSystemAudio
            config.excludesCurrentProcessAudio = true   // 이 앱의 효과음은 녹음되지 않음
            config.sampleRate = 48_000
            config.channelCount = 2
            config.captureMicrophone = includeMicrophone

            let fileURL: URL
            if mode.isVideo {
                fileURL = try makeOutputURL(ext: videoFormat.fileExtension)
                pendingAudioURL = nil
            } else {
                fileURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("RecMac-\(UUID().uuidString).mp4")
                pendingAudioURL = try makeOutputURL(ext: "m4a")
            }

            let recordingConfig = SCRecordingOutputConfiguration()
            recordingConfig.outputURL = fileURL
            // 오디오 모드는 임시 mp4로 받은 뒤 m4a로 바꾼다
            recordingConfig.outputFileType = mode.isVideo ? videoFormat.fileType : .mp4
            recordingConfig.videoCodecType = mode.isVideo ? videoFormat.codec : .h264

            let stream = SCStream(filter: filter, configuration: config, delegate: self)
            try stream.addStreamOutput(sink, type: .screen, sampleHandlerQueue: sinkQueue)
            if includeSystemAudio {
                try stream.addStreamOutput(sink, type: .audio, sampleHandlerQueue: sinkQueue)
            }
            if includeMicrophone {
                try stream.addStreamOutput(sink, type: .microphone, sampleHandlerQueue: sinkQueue)
            }

            let output = SCRecordingOutput(configuration: recordingConfig, delegate: self)
            try stream.addRecordingOutput(output)
            didFinishWriting = false
            try await stream.startCapture()

            self.stream = stream
            self.recordingOutput = output
            currentFileURL = fileURL
            if let tracking {
                startWindowTracking(windowID: tracking.windowID, displayFrame: tracking.displayFrame,
                                    config: config, initialRect: sourceRect)
            }
            isRecording = true
            startTimer()
            play("Glass")
            island.showRecording(audioOnly: !mode.isVideo) { [weak self] in
                Task { await self?.stop() }
            }
        } catch {
            post(describe(error), isError: true)
            pendingAudioURL = nil
            // 고른 창이 닫혔으면 선택을 풀어서 다시 고를 수 있게
            if case RecorderError.noWindow = error {
                selectedWindowID = nil
                self.mode = nil
            }
            cleanup()
        }
    }

    func stop() async {
        guard let stream else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            try await stream.stopCapture()
        } catch {
            post(describe(error), isError: true)
        }
        play("Pop")

        let fileURL = currentFileURL
        let audioURL = pendingAudioURL
        let toolbarHidden = !restoreToolbarAfterRecording     // 툴바가 안 보이면 알림 대신 노치로 알려 줌
        cleanup(keepIsland: toolbarHidden)
        await waitForFileFinished()

        guard let fileURL else {
            island.hide()
            return
        }
        var saved: URL?
        if let audioURL {
            do {
                try await exportAudio(from: fileURL, to: audioURL)
                try? FileManager.default.removeItem(at: fileURL)
                saved = audioURL
            } catch {
                post(RecorderError.exportFailed.localizedDescription, isError: true)
            }
        } else {
            saved = fileURL
        }
        if let saved {
            lastFileURL = saved
            post(tr("저장했어요 · \(saved.lastPathComponent)", "Saved · \(saved.lastPathComponent)"), fileURL: saved)
            if toolbarHidden {
                island.flashSaved { [weak self] in self?.revealLastFile() }
            }
        } else {
            island.hide()
        }
    }

    private func exportAudio(from source: URL, to destination: URL) async throws {
        let asset = AVURLAsset(url: source)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw RecorderError.exportFailed
        }
        try await export.export(to: destination, as: .m4a)
    }

    /// 녹화 파일이 디스크에 다 써질 때까지 기다린다 (최대 3초)
    private func waitForFileFinished() async {
        if didFinishWriting { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            finishWaiter = cont
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                MainActor.assumeIsolated {
                    self?.finishWaiter?.resume()
                    self?.finishWaiter = nil
                }
            }
        }
    }

    fileprivate func markFinishedWriting() {
        didFinishWriting = true
        finishWaiter?.resume()
        finishWaiter = nil
    }

    // MARK: - Helpers

    private func cleanup(keepIsland: Bool = false) {
        timer?.invalidate()
        timer = nil
        startDate = nil
        trackTimer?.invalidate()
        trackTimer = nil
        trackedSourceRect = nil
        stream = nil
        recordingOutput = nil
        currentFileURL = nil
        pendingAudioURL = nil
        isRecording = false
        elapsedText = "00:00"
        if !keepIsland { island.hide() }
        if restoreToolbarAfterRecording {
            showMainWindow()
        } else {
            highlight.hide()
        }
        restoreToolbarAfterRecording = true
    }

    /// 지금 마우스가 있는 화면의 가운데 아래
    private func toolbarHomeOrigin(for w: NSWindow) -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens[0]
        let v = screen.visibleFrame
        return NSPoint(x: (v.midX - w.frame.width / 2).rounded(), y: v.minY + 8)
    }

    /// 데스크탑을 넘기거나 모니터가 바뀌면 가운데 아래로 부드럽게 옮긴다
    func repositionToolbar() {
        guard let w = mainWindow, isToolbarVisible else { return }
        let home = toolbarHomeOrigin(for: w)
        guard w.frame.origin != home else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
            w.animator().setFrame(NSRect(origin: home, size: w.frame.size), display: true)
        }
    }

    /// 창을 닫지 않고 아래로 살짝 내려가며 사라지게 한다 (닫으면 맥이 앱을 종료할 수 있음)
    private func hideMainWindow(toMenuBar: Bool = false) {
        guard let w = mainWindow, !w.ignoresMouseEvents else { return }
        let home = w.frame.origin
        w.ignoresMouseEvents = true

        // 접을 때: 작아지면서 메뉴 막대 아이콘 쪽으로 쏙 빨려 올라간다
        if toMenuBar, let icon = statusItemFrame() {
            let barCenterFromBottom: CGFloat = 28        // 작아진 바의 가운데 (패널 아래 기준)
            let dest = NSPoint(x: (icon.midX - w.frame.width / 2).rounded(),
                               y: (icon.midY - barCenterFromBottom).rounded())
            let size = w.frame.size
            flyTick += 1    // 툴바 모양: 살짝 눌렸다가(예비동작) 세로로 늘어나며 작아짐
            // 1) 예비동작: 아래로 살짝 가라앉았다가
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.13
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                w.animator().setFrame(NSRect(origin: NSPoint(x: home.x, y: home.y - 10), size: size), display: true)
            }, completionHandler: {
                // 2) 출발: 점점 빨라지며 메뉴 막대 아이콘 속으로
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.4
                    ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.55, 0, 0.85, 0.35)
                    w.animator().alphaValue = 0
                    w.animator().setFrame(NSRect(origin: dest, size: size), display: true)
                }
            })
            return
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            w.animator().alphaValue = 0
            w.animator().setFrame(NSRect(origin: NSPoint(x: home.x, y: home.y - 24), size: w.frame.size), display: true)
        }
    }

    /// 아래에서 스윽 올라오며 나타난다
    func showMainWindow() {
        guard let w = mainWindow else { return }
        let home = toolbarHomeOrigin(for: w)
        w.ignoresMouseEvents = false
        if !w.isVisible { w.orderFrontRegardless() }
        guard w.alphaValue < 0.99 else { repositionToolbar(); return }
        if w.alphaValue < 0.05 {
            w.setFrame(NSRect(origin: NSPoint(x: home.x, y: home.y - 40), size: w.frame.size), display: false)
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.42
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
            w.animator().alphaValue = 1
            w.animator().setFrame(NSRect(origin: home, size: w.frame.size), display: true)
        }
    }

    /// 고르기를 마치거나 취소하면 RecMac를 다시 앞으로
    private func bringToFront() {
        showMainWindow()
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func play(_ name: String) {
        guard playSounds else { return }
        NSSound(named: name)?.play()
    }

    /// 창 모드 녹화 중 창을 옮기면 녹화 영역도 따라가게 한다
    private func startWindowTracking(windowID: CGWindowID, displayFrame: CGRect,
                                     config: SCStreamConfiguration, initialRect: CGRect?) {
        trackedSourceRect = initialRect
        trackTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let stream = self.stream,
                      let frame = WindowList.frame(of: windowID) else { return } // 다른 데스크탑으로 가면 마지막 위치 유지
                let rect = frame
                    .offsetBy(dx: -displayFrame.minX, dy: -displayFrame.minY)
                    .intersection(CGRect(origin: .zero, size: displayFrame.size))
                guard !rect.isNull, rect.width > 2, rect.height > 2,
                      rect != self.trackedSourceRect else { return }
                self.trackedSourceRect = rect
                config.sourceRect = rect
                Task { try? await stream.updateConfiguration(config) }
            }
        }
    }

    private func startTimer() {
        startDate = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let start = self.startDate else { return }
                let seconds = Int(Date().timeIntervalSince(start))
                let text = seconds >= 3600
                    ? String(format: "%d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60)
                    : String(format: "%02d:%02d", seconds / 60, seconds % 60)
                if text != self.elapsedText {
                    self.elapsedText = text
                    self.island.update(elapsed: text)
                }
            }
        }
    }

    private func outputFolder() throws -> URL {
        let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0]
        let folder = movies.appendingPathComponent("RecMac", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func makeOutputURL(ext: String) throws -> URL {
        let folder = try outputFolder()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let prefix = ext == "m4a" ? tr("오디오", "Audio") : tr("녹화", "Recording")
        return folder.appendingPathComponent("\(prefix) \(formatter.string(from: Date())).\(ext)")
    }

    private func describe(_ error: Error) -> String {
        if let scError = error as? SCStreamError, scError.code == .userDeclined {
            return tr("화면 녹화 권한이 필요해요. 시스템 설정 > 개인정보 보호 및 보안 > 화면 및 시스템 오디오 녹음에서 RecMac를 켠 뒤 앱을 다시 실행해 주세요.", "Screen recording permission is needed. Turn on RecMac in System Settings > Privacy & Security > Screen & System Audio Recording, then reopen the app.")
        }
        return error.localizedDescription
    }
}

extension Recorder: SCStreamDelegate, SCRecordingOutputDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            self.post(self.describe(error), isError: true)
            self.cleanup()
        }
    }

    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        Task { @MainActor in
            self.post(tr("파일 저장 실패: \(error.localizedDescription)", "Couldn't save the file: \(error.localizedDescription)"), isError: true)
            self.markFinishedWriting()
        }
    }

    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in
            self.markFinishedWriting()
        }
    }
}

/// 받은 샘플을 그냥 버리는 출력 (오디오 기록 안정용)
final class SampleSink: NSObject, SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {}
}
