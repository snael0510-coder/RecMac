import SwiftUI
import AppKit

// MARK: - 창 정보 (CoreGraphics 전역 좌표: 주 화면 왼쪽 위가 원점)

struct WindowInfo: Equatable {
    let id: CGWindowID
    let frame: CGRect
    let appName: String
}

enum WindowList {
    /// 화면에 보이는 일반 창들, 앞에 있는 창부터
    static func onScreen(excludingPID pid: pid_t) -> [WindowInfo] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                     kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let owner = info[kCGWindowOwnerPID as String] as? Int, pid_t(owner) != pid,
                  let number = info[kCGWindowNumber as String] as? Int,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  rect.width > 80, rect.height > 60,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0.05 else { return nil }
            let name = info[kCGWindowOwnerName as String] as? String ?? ""
            return WindowInfo(id: CGWindowID(number), frame: rect, appName: name)
        }
    }

    /// 특정 창의 현재 위치. 최소화되었거나 다른 데스크탑에 있으면 nil
    static func frame(of id: CGWindowID) -> CGRect? {
        guard let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]],
              let info = list.first,
              (info[kCGWindowIsOnscreen as String] as? Bool) == true,
              let bounds = info[kCGWindowBounds as String] as? NSDictionary else { return nil }
        return CGRect(dictionaryRepresentation: bounds as CFDictionary)
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
    /// 전역 좌표에서 이 화면의 영역 (왼쪽 위 원점)
    var globalBounds: CGRect { CGDisplayBounds(displayID) }
}

func makeOverlayWindow(for screen: NSScreen, level: NSWindow.Level, clickThrough: Bool) -> NSWindow {
    let window: NSWindow = clickThrough
        ? NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        : SelectionWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = false
    window.ignoresMouseEvents = clickThrough
    window.level = level
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    window.isReleasedWhenClosed = false
    return window
}

/// 고르기 화면을 닫을 때 똑같이 스르륵 사라지게
func fadeOutAndClose(_ windows: [NSWindow], duration: TimeInterval = 0.16) {
    NSAnimationContext.runAnimationGroup({ ctx in
        ctx.duration = duration
        ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
        for w in windows { w.animator().alphaValue = 0 }
    }, completionHandler: {
        for w in windows {
            w.orderOut(nil)
            w.alphaValue = 1
        }
    })
}

/// 고르기 화면이 열릴 때 똑같이 스르륵 나타나게 (어두운 막 + 안내 바)
let pickAppear = Animation.easeOut(duration: 0.18)

/// SwiftUI 뷰를 창 크기에 맞게 넣는다 (창 크기를 바꾸지 않도록)
func hosting<V: View>(_ view: V) -> NSHostingView<V> {
    let host = NSHostingView(rootView: view)
    host.sizingOptions = []
    return host
}

// MARK: - 구멍 뚫린 어두운 막 (구멍 위치가 부드럽게 움직임)

struct DimShape: Shape {
    var hole: CGRect
    var cornerRadius: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(hole.origin.x, hole.origin.y), AnimatablePair(hole.size.width, hole.size.height)) }
        set { hole = CGRect(x: newValue.first.first, y: newValue.first.second,
                            width: max(newValue.second.first, 0), height: max(newValue.second.second, 0)) }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addRect(rect)
        if hole.width > 0.5, hole.height > 0.5 {
            let r = min(cornerRadius, hole.width / 2, hole.height / 2)
            p.addRoundedRect(in: hole, cornerSize: CGSize(width: r, height: r), style: .continuous)
        }
        return p
    }
}

private let smooth = Animation.spring(response: 0.3, dampingFraction: 0.86)

// MARK: - 계속 떠 있는 강조 표시 (클릭은 통과, 녹화 영상에는 안 찍힘)

@MainActor
final class HighlightModel: ObservableObject {
    @Published var active = false        // 대상이 있을 때만 어둡게
    @Published var rect: CGRect?         // 이 화면 기준 좌표
    @Published var recording = false
    var cornerRadius: CGFloat = 0
}

@MainActor
final class HighlightOverlay {
    private struct Panel {
        let window: NSWindow
        let bounds: CGRect
        let model: HighlightModel
    }

    private var panels: [Panel] = []
    private var timer: Timer?
    private var provider: (() -> CGRect?)?
    private var recording = false
    private var cornerRadius: CGFloat = 0

    func show(cornerRadius: CGFloat, provider: @escaping () -> CGRect?) {
        self.provider = provider
        self.cornerRadius = cornerRadius
        if panels.isEmpty { build() }
        for panel in panels { panel.model.cornerRadius = cornerRadius }
        update()
        if timer == nil {
            // 창이 움직여도 따라가도록 주기적으로 갱신
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.update() }
            }
        }
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        provider = nil
        for panel in panels { panel.window.orderOut(nil) }
        panels.removeAll()
    }

    func setRecording(_ value: Bool) {
        recording = value
        for panel in panels { panel.model.recording = value }
    }

    private func build() {
        for screen in NSScreen.screens {
            let model = HighlightModel()
            model.recording = recording
            model.cornerRadius = cornerRadius
            let window = makeOverlayWindow(for: screen, level: .floating, clickThrough: true)
            window.contentView = hosting(HighlightView(model: model))
            window.setFrame(screen.frame, display: false)
            window.orderFrontRegardless()
            panels.append(Panel(window: window, bounds: screen.globalBounds, model: model))
        }
    }

    private func update() {
        let target = provider?()
        for panel in panels {
            let active = target != nil
            if panel.model.active != active { panel.model.active = active }
            var local: CGRect?
            if let target, target.intersects(panel.bounds) {
                local = target.offsetBy(dx: -panel.bounds.minX, dy: -panel.bounds.minY)
            }
            if panel.model.rect != local { panel.model.rect = local }
        }
    }
}

private struct HighlightView: View {
    @ObservedObject var model: HighlightModel
    @State private var appeared = false

    var body: some View {
        ZStack {
            DimShape(hole: model.rect ?? .zero, cornerRadius: model.cornerRadius)
                .fill(Color.black.opacity(model.active ? 0.4 : 0), style: FillStyle(eoFill: true))

            if let r = model.rect {
                RoundedRectangle(cornerRadius: model.cornerRadius + 2, style: .continuous)
                    .stroke(model.recording ? Color.brand : Color.white.opacity(0.55),
                            style: StrokeStyle(lineWidth: model.recording ? 2 : 1))
                    .frame(width: r.width + 4, height: r.height + 4)
                    .position(x: r.midX, y: r.midY)
            }
        }
        .opacity(appeared ? 1 : 0)
        .animation(.easeOut(duration: 0.12), value: model.rect)
        .animation(.easeInOut(duration: 0.25), value: model.recording)
        .animation(.easeInOut(duration: 0.25), value: model.active)
        .onAppear { withAnimation(.easeOut(duration: 0.25)) { appeared = true } }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }
}

// MARK: - 화면에서 창 클릭해서 고르기

@MainActor
final class WindowPicker {
    private var windows: [NSWindow] = []
    private var keyMonitor: Any?
    private var mouseMonitor: Any?
    private var continuation: CheckedContinuation<CGWindowID?, Never>?

    func pick() async -> CGWindowID? {
        return await withCheckedContinuation { cont in
            continuation = cont
            let mainID = NSScreen.main?.displayID
            for screen in NSScreen.screens {
                let window = makeOverlayWindow(for: screen, level: .screenSaver, clickThrough: false)
                window.contentView = hosting(WindowPickView(
                    origin: screen.globalBounds.origin,
                    showHint: screen.displayID == mainID
                ) { [weak self] id in
                    MainActor.assumeIsolated { self?.finish(id) }
                })
                window.setFrame(screen.frame, display: false)
                window.orderFrontRegardless()
                windows.append(window)
            }
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 53 { // ESC
                    MainActor.assumeIsolated { self?.finish(nil) }
                    return nil
                }
                return event
            }
            // 우클릭으로도 취소
            mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] _ in
                MainActor.assumeIsolated { self?.finish(nil) }
                return nil
            }
            // ESC가 먹도록: 전역으로도 잡고, 이 앱도 앞으로
            HotKeyCenter.shared.captureEscape { [weak self] in self?.finish(nil) }
            NSApp.activate(ignoringOtherApps: true)
            windows.first?.makeKeyAndOrderFront(nil)
        }
    }

    private func finish(_ id: CGWindowID?) {
        guard continuation != nil else { return }
        HotKeyCenter.shared.releaseEscape()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
        let closing = windows
        windows.removeAll()
        fadeOutAndClose(closing)
        continuation?.resume(returning: id)
        continuation = nil
    }
}

private struct WindowPickView: View {
    let origin: CGPoint
    let showHint: Bool
    let onFinish: (CGWindowID?) -> Void

    @State private var hovered: WindowInfo?
    @State private var hole: CGRect = .zero
    @State private var appeared = false
    @State private var picked = false
    @State private var candidates: [WindowInfo] = []
    @State private var lastRefresh = Date.distantPast

    /// 창 위치는 계속 바뀔 수 있으니(데스크탑 전환, 창 이동) 짧은 간격으로 다시 읽는다
    private func refreshCandidates(force: Bool = false) {
        guard force || Date().timeIntervalSince(lastRefresh) > 0.12 else { return }
        candidates = WindowList.onScreen(excludingPID: getpid())
        lastRefresh = Date()
    }

    private func local(_ rect: CGRect) -> CGRect {
        rect.offsetBy(dx: -origin.x, dy: -origin.y)
    }

    private func setTarget(_ window: WindowInfo?) {
        guard window?.id != hovered?.id else { return }
        if let window {
            let r = local(window.frame)
            if hovered == nil && hole == .zero {
                hole = r               // 처음엔 바로 그 자리에
                withAnimation(smooth) { hovered = window }
            } else {
                withAnimation(smooth) {
                    hovered = window
                    hole = r
                }
            }
        } else {
            withAnimation(smooth) {
                hovered = nil
                hole = CGRect(x: hole.midX, y: hole.midY, width: 0, height: 0)
            }
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                DimShape(hole: hole, cornerRadius: 10)
                    .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))

                if showHint {
                    PickHint(icon: "cursorarrow.click",
                             text: tr("녹화할 창을 클릭하세요", "Click a window to record")) { onFinish(nil) }
                        .position(x: geo.size.width / 2, y: geo.size.height - 70)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .opacity(appeared ? 1 : 0)
            .onAppear {
                refreshCandidates(force: true)
                withAnimation(pickAppear) { appeared = true }
            }
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let point):
                    NSCursor.pointingHand.set()
                    refreshCandidates()
                    setTarget(candidates.first { local($0.frame).contains(point) })
                case .ended:
                    setTarget(nil)
                }
            }
            .onReceive(NSWorkspace.shared.notificationCenter
                        .publisher(for: NSWorkspace.activeSpaceDidChangeNotification)) { _ in
                // 데스크탑을 넘기면 이전 위치를 버리고 새로 읽는다
                refreshCandidates(force: true)
                setTarget(nil)
            }
            .onTapGesture(coordinateSpace: .local) { point in
                // 클릭한 순간의 실제 창을 다시 확인 (허공 선택 방지)
                refreshCandidates(force: true)
                guard let target = candidates.first(where: { local($0.frame).contains(point) }) else {
                    onFinish(nil)          // 빈 곳 클릭 = 취소
                    return
                }
                setTarget(target)
                withAnimation(.easeOut(duration: 0.1)) { picked = true }
                onFinish(target.id)
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - 고르기 화면 공통 안내 바

struct PickHint: View {
    let icon: String
    let text: String
    let onCancel: () -> Void
    @State private var shown = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
            Text(text)
                .font(.system(size: 14, weight: .semibold))
            Button(action: onCancel) {
                Text(tr("취소 (ESC)", "Cancel (esc)"))
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.18)))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(Capsule().fill(.ultraThinMaterial))
        .environment(\.colorScheme, .dark)
        .fixedSize()
        .offset(y: shown ? 0 : 14)
        .opacity(shown ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82).delay(0.06)) { shown = true }
        }
    }
}

// MARK: - 메인 창 참조 얻기

struct WindowAccessor: NSViewRepresentable {
    let configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window { configure(window) }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
