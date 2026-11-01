import SwiftUI
import AppKit

@MainActor
final class CountdownModel: ObservableObject {
    @Published var number = 3
    @Published var visible = false
}

/// 녹화 대상 가운데에 3, 2, 1 숫자를 띄운다. 클릭은 통과하고 녹화에는 찍히지 않는다.
@MainActor
final class CountdownOverlay {
    private var cancelled = false

    func cancel() { cancelled = true }

    /// 끝까지 세면 true, 중간에 취소되면 false
    func run(around target: CGRect?, seconds: Int = 3, tick: Bool) async -> Bool {
        cancelled = false
        let center = target.map { CGPoint(x: $0.midX, y: $0.midY) }
        let screen = center.flatMap { c in NSScreen.screens.first { $0.globalBounds.contains(c) } }
            ?? NSScreen.main ?? NSScreen.screens[0]
        let bounds = screen.globalBounds
        let localCenter = center.map { CGPoint(x: $0.x - bounds.minX, y: $0.y - bounds.minY) }
            ?? CGPoint(x: bounds.width / 2, y: bounds.height / 2)

        let model = CountdownModel()
        model.number = seconds
        let window = makeOverlayWindow(for: screen, level: .screenSaver, clickThrough: true)
        window.contentView = hosting(CountdownView(model: model, center: localCenter))
        window.setFrame(screen.frame, display: false)
        window.orderFrontRegardless()

        model.visible = true
        countdown: for n in stride(from: seconds, through: 1, by: -1) {
            model.number = n
            if tick { NSSound(named: "Tink")?.play() }
            for _ in 0..<20 {            // 1초를 잘게 나눠 취소를 바로 반영
                if cancelled { break countdown }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
        model.visible = false
        try? await Task.sleep(nanoseconds: 150_000_000)
        window.orderOut(nil)
        return !cancelled
    }
}

private struct CountdownView: View {
    @ObservedObject var model: CountdownModel
    let center: CGPoint

    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .frame(width: 168, height: 168)
                .shadow(color: .black.opacity(0.35), radius: 20, y: 6)

            Text("\(model.number)")
                .font(.system(size: 88, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .id(model.number)
                .transition(.asymmetric(
                    insertion: .scale(scale: 1.5).combined(with: .opacity),
                    removal: .scale(scale: 0.6).combined(with: .opacity)))
        }
        .scaleEffect(model.visible ? 1 : 0.7)
        .opacity(model.visible ? 1 : 0)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: model.number)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: model.visible)
        .position(center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }
}
