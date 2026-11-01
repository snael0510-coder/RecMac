import SwiftUI
import AppKit

/// 화면 전체를 어둡게 덮고 드래그로 영역을 고르게 한다. ESC로 취소.
@MainActor
final class AreaSelector {
    private var window: NSWindow?
    private var keyMonitor: Any?
    private var mouseMonitor: Any?
    private var continuation: CheckedContinuation<CGRect?, Never>?

    func select(on screen: NSScreen) async -> CGRect? {
        await withCheckedContinuation { cont in
            continuation = cont

            let w = SelectionWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = false
            w.level = .screenSaver
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            w.isReleasedWhenClosed = false
            w.contentView = hosting(AreaSelectionView { [weak self] rect in
                MainActor.assumeIsolated { self?.finish(rect) }
            })
            w.setFrame(screen.frame, display: true)

            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 53 { // ESC
                    MainActor.assumeIsolated { self?.finish(nil) }
                    return nil
                }
                return event
            }

            mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] _ in
                MainActor.assumeIsolated { self?.finish(nil) }
                return nil
            }
            HotKeyCenter.shared.captureEscape { [weak self] in self?.finish(nil) }
            NSApp.activate(ignoringOtherApps: true)
            w.makeKeyAndOrderFront(nil)
            window = w
        }
    }

    private func finish(_ rect: CGRect?) {
        guard continuation != nil else { return }
        HotKeyCenter.shared.releaseEscape()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
        if let window { fadeOutAndClose([window]) }
        window = nil
        continuation?.resume(returning: rect)
        continuation = nil
    }
}

final class SelectionWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

private struct AreaSelectionView: View {
    let onFinish: (CGRect?) -> Void
    @State private var start: CGPoint?
    @State private var appeared = false
    @State private var current: CGPoint?

    private var rect: CGRect? {
        guard let s = start, let c = current else { return nil }
        return CGRect(x: min(s.x, c.x), y: min(s.y, c.y), width: abs(s.x - c.x), height: abs(s.y - c.y))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // 선택 영역만 뚫린 어두운 막
                Path { p in
                    p.addRect(CGRect(origin: .zero, size: geo.size))
                    if let r = rect { p.addRect(r) }
                }
                .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))

                if let r = rect {
                    Rectangle()
                        .stroke(Color.white, lineWidth: 1.5)
                        .frame(width: r.width, height: r.height)
                        .position(x: r.midX, y: r.midY)

                    Text("\(Int(r.width)) × \(Int(r.height))")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.black.opacity(0.7)))
                        .position(x: r.midX, y: r.maxY + 20 > geo.size.height - 8 ? r.minY - 20 : r.maxY + 20)
                } else {
                    PickHint(icon: "rectangle.dashed",
                             text: tr("드래그해서 녹화할 영역을 선택하세요", "Drag to select an area")) { onFinish(nil) }
                        .position(x: geo.size.width / 2, y: geo.size.height - 70)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.15), value: rect == nil)
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .opacity(appeared ? 1 : 0)
            .onAppear { withAnimation(pickAppear) { appeared = true } }
            .onContinuousHover { _ in NSCursor.crosshair.set() }
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .local)
                    .onChanged { value in
                        if start == nil { start = value.startLocation }
                        current = value.location
                    }
                    .onEnded { _ in
                        if let r = rect, r.width >= 20, r.height >= 20 {
                            onFinish(r.integral)
                        } else {
                            start = nil
                            current = nil
                        }
                    }
            )
        }
        .ignoresSafeArea()
    }
}
