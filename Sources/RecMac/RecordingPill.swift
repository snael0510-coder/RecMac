import SwiftUI
import AppKit

// 노치(카메라) 주변의 다이나믹 아일랜드
// - idle: 툴바가 접혔을 때. 마우스를 올리면 [녹화] [툴바 열기]
// - recording: 녹화 중. 마우스를 올리면 [녹화 정지]
// 이 앱의 창이라 녹화 영상에는 찍히지 않는다.

enum IslandState {
    case hidden, idle, recording, saved
}

@MainActor
final class IslandModel: ObservableObject {
    @Published var state: IslandState = .hidden
    @Published var shown = false          // false면 노치 속으로 쏙 들어간 상태
    @Published var elapsed = "00:00"
    @Published var modeIcon: String?
    var audioOnly = false
    var notchWidth: CGFloat = 0           // 0이면 노치 없는 화면
    var barHeight: CGFloat = 32
    var onStop: () -> Void = {}
    var onRecord: () -> Void = {}
    var onOpen: () -> Void = {}
}

private final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }     // 버튼 클릭을 확실히 받기 위해
    override var canBecomeMain: Bool { false }
}

@MainActor
final class Island {
    private var panel: NSPanel?
    private let model = IslandModel()
    private var spaceObserver: NSObjectProtocol?
    private var bounceWork: DispatchWorkItem?
    private var hideWork: DispatchWorkItem?

    func showIdle(modeIcon: String?, onRecord: @escaping () -> Void, onOpen: @escaping () -> Void) {
        model.modeIcon = modeIcon
        model.onRecord = onRecord
        model.onOpen = onOpen
        present(.idle)
    }

    func showRecording(audioOnly: Bool, onStop: @escaping () -> Void) {
        model.audioOnly = audioOnly
        model.onStop = onStop
        model.elapsed = "00:00"
        present(.recording)
    }

    /// 녹화가 끝났을 때 REC 자리에서 '저장됨'으로 바뀌었다가 잠시 뒤 들어간다
    func flashSaved(onReveal: @escaping () -> Void) {
        model.onOpen = onReveal
        present(.saved)
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.model.state == .saved else { return }
                self.hide()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: work)
    }

    func update(elapsed: String) {
        model.elapsed = elapsed
    }

    func hide() {
        guard let panel else { return }
        bounceWork?.cancel()
        hideWork?.cancel()
        model.shown = false
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.model.shown, self.panel === panel else { return }
                panel.orderOut(nil)
                self.panel = nil
                self.model.state = .hidden
                if let o = self.spaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(o) }
                self.spaceObserver = nil
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
    }

    private func present(_ state: IslandState) {
        hideWork?.cancel()
        if panel == nil { build() }
        let wasShown = model.shown
        model.state = state
        if !wasShown {
            // 다음 프레임에 노치에서 쭉 늘어나며 등장
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
                MainActor.assumeIsolated { self?.model.shown = true }
            }
        }
    }

    private func build() {
        // 노치가 있는 화면(맥북 내장 화면)을 우선 사용
        let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
            ?? NSScreen.main ?? NSScreen.screens[0]
        var notch: CGFloat = 0
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            notch = max(0, screen.frame.width - left.width - right.width)
        }
        model.notchWidth = notch
        model.barHeight = notch > 0 ? screen.safeAreaInsets.top : 32
        model.shown = false

        let size = CGSize(width: notch + 420, height: 150)
        let frame = NSRect(x: screen.frame.midX - size.width / 2,
                           y: screen.frame.maxY - size.height,
                           width: size.width, height: size.height)
        let panel = IslandPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)  // 메뉴 막대 위
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.contentView = hosting(IslandView(model: model))
        panel.setFrame(frame, display: false)
        panel.orderFrontRegardless()
        self.panel = panel

        // 데스크탑(Space)을 넘기면 노치 속으로 들어갔다가 다시 튀어나옴
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.bounce() }
        }
    }

    private func bounce() {
        guard panel != nil, model.shown else { return }
        bounceWork?.cancel()
        model.shown = false
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.panel != nil, self.model.state != .hidden else { return }
                self.model.shown = true
            }
        }
        bounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }
}

private struct IslandView: View {
    @ObservedObject var model: IslandModel
    @State private var hovering = false
    @State private var pulse = false

    private var hasNotch: Bool { model.notchWidth > 0 }
    private var isRecording: Bool { model.state == .recording }
    private var expanded: Bool { model.shown && hovering }
    private var isSaved: Bool { model.state == .saved }
    private var ear: CGFloat { isRecording ? 84 : (isSaved ? 72 : 46) }

    // 숨김 = 노치와 같은 크기(검정이라 안 보임) → 등장 = 양옆으로 늘어남 → 호버 = 아래로 펼쳐짐
    private var width: CGFloat {
        if !model.shown { return hasNotch ? model.notchWidth : 40 }
        let base = hasNotch ? model.notchWidth + ear * 2 : (isRecording ? 176 : (isSaved ? 150 : 96))
        return expanded ? max(base + 36, isRecording ? 0 : 250) : base
    }
    private var height: CGFloat {
        if !model.shown { return hasNotch ? model.barHeight : 12 }
        return expanded ? model.barHeight + 48 : model.barHeight
    }
    private var radius: CGFloat {
        if !model.shown { return 10 }
        return expanded ? 24 : (hasNotch ? 14 : 16)
    }

    private var shape: AnyShape {
        if hasNotch {
            // 위쪽은 화면 끝과 이어지고 아래만 둥근 모양 → 노치가 늘어난 것처럼 보임
            return AnyShape(UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: radius,
                                                   bottomTrailingRadius: radius, topTrailingRadius: 0,
                                                   style: .continuous))
        }
        return AnyShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    /// 나올 땐 쫀득하게 튀고, 들어갈 땐 빠르게
    private var morph: Animation {
        model.shown
            ? .spring(response: 0.55, dampingFraction: 0.6, blendDuration: 0.1)
            : .spring(response: 0.3, dampingFraction: 0.92)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                shape
                    .fill(Color.black)
                    .frame(width: width, height: height)

                content
                    .frame(width: width, height: height, alignment: .top)
                    .opacity(model.shown ? 1 : 0)
                    .blur(radius: model.shown ? 0 : 6)
                    .animation(.easeOut(duration: 0.22).delay(model.shown ? 0.12 : 0), value: model.shown)
            }
            .frame(width: width, height: height)
            .clipShape(shape)
            .contentShape(shape)
            .shadow(color: .black.opacity(hasNotch ? 0 : 0.35), radius: 10, y: 4)
            .offset(y: hasNotch ? 0 : (model.shown ? 8 : -20))
            .onHover { h in
                withAnimation(.spring(response: 0.42, dampingFraction: 0.68)) { hovering = h }
            }
            .animation(morph, value: model.shown)
            .animation(.spring(response: 0.5, dampingFraction: 0.68), value: model.state)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { pulse = true }
    }

    private var content: some View {
        VStack(spacing: 10) {
            HStack(spacing: 0) {
                leftEar
                    .frame(maxWidth: .infinity, alignment: .leading)
                if hasNotch {
                    Color.clear.frame(width: model.notchWidth)
                }
                rightEar
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, isRecording ? 16 : 14)
            .frame(height: model.barHeight)

            if expanded {
                actions
                    .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .top)))
            }
        }
    }

    @ViewBuilder
    private var leftEar: some View {
        if isRecording {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.brand)
                    .frame(width: 8, height: 8)
                    .shadow(color: Color.brand.opacity(0.9), radius: pulse ? 5 : 1)
                    .opacity(pulse ? 0.45 : 1)
                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
                if model.audioOnly {
                    Image(systemName: "waveform")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.brand)
                        .symbolEffect(.variableColor.iterative, options: .repeating)
                } else {
                    Text("REC")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.brand)
                }
            }
        } else if isSaved {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: isSaved)
        } else {
            Image(systemName: "record.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.brand)
        }
    }

    @ViewBuilder
    private var rightEar: some View {
        if isRecording {
            Text(model.elapsed)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.2), value: model.elapsed)
        } else if isSaved {
            Text(tr("저장됨", "Saved"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
        } else {
            Image(systemName: model.modeIcon ?? "ellipsis")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
        }
    }

    @ViewBuilder
    private var actions: some View {
        if isRecording {
            IslandButton(icon: "stop.fill", title: tr("녹화 정지", "Stop"), prominent: true) { model.onStop() }
        } else if isSaved {
            IslandButton(icon: "folder", title: tr("파일 보기", "Show file"), prominent: false) { model.onOpen() }
        } else {
            HStack(spacing: 8) {
                if model.modeIcon != nil {
                    IslandButton(icon: "record.circle.fill", title: tr("녹화", "Record"), prominent: true) { model.onRecord() }
                }
                IslandButton(icon: "menubar.dock.rectangle", title: tr("툴바 열기", "Open toolbar"), prominent: false) { model.onOpen() }
            }
        }
    }
}

private struct IslandButton: View {
    let icon: String
    let title: String
    let prominent: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(Capsule().fill(prominent ? Color.brand : Color.white.opacity(hovering ? 0.22 : 0.14)))
            .scaleEffect(hovering ? 1.04 : 1)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { hovering = h } }
    }
}
