import SwiftUI
import AppKit

/// 맥 스크린샷 툴바(⇧⌘5) 스타일의 얇은 녹화 바
/// 기본: [닫기] | [선택 영역][전체 화면][창][오디오] | [내부 소리][마이크] | [고급] [최근 파일] [● 녹화]
/// 고급을 누르면: [커서][타이머][화질][설정] 이 펼쳐진다
struct ToolbarView: View {
    @EnvironmentObject var recorder: Recorder
    @State private var showDisplayList = false

    private var locked: Bool { recorder.isRecording || recorder.isBusy || recorder.countdownActive }
    private var isVideoMode: Bool { recorder.mode?.isVideo ?? true }

    var body: some View {
        VStack(spacing: 10) {
            noticeView
            bar
        }
        .padding(.horizontal, 18)
        .padding(.top, 44)  // 호버 설명이 바 위로 열릴 공간
        .padding(.bottom, 18)
        .keyframeAnimator(initialValue: FlyValues(), trigger: recorder.flyTick) { content, v in
            content.scaleEffect(x: v.sx, y: v.sy, anchor: .bottom)
        } keyframes: { _ in
            // 예비동작(눌림) → 출발하며 가로로 좁고 세로로 길게 늘어남 → 다음에 열 때를 위해 원래 크기로
            KeyframeTrack(\.sx) {
                SpringKeyframe(1.06, duration: 0.13, spring: .snappy)
                CubicKeyframe(0.2, duration: 0.4)
                LinearKeyframe(0.2, duration: 0.15)
                MoveKeyframe(1)
            }
            KeyframeTrack(\.sy) {
                SpringKeyframe(0.88, duration: 0.13, spring: .snappy)
                CubicKeyframe(0.38, duration: 0.4)
                LinearKeyframe(0.38, duration: 0.15)
                MoveKeyframe(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: recorder.notice)
        .task { await recorder.refreshContent() }
    }

    // MARK: - 바

    private var bar: some View {
        HStack(spacing: 2) {
            CloseButton { recorder.collapseToIsland() }

            BarDivider()

            Group {
                ModeButton(mode: .area, isSelected: recorder.mode == .area,
                           tip: recorder.tip(for: .area)) {
                    Task { await recorder.chooseArea() }
                }
                ModeButton(mode: .display, isSelected: recorder.mode == .display,
                           tip: recorder.tip(for: .display)) {
                    recorder.chooseDisplay()
                    if recorder.displays.count > 1 { showDisplayList = true }
                }
                .popover(isPresented: $showDisplayList, arrowEdge: .top) { displayList }
                ModeButton(mode: .window, isSelected: recorder.mode == .window,
                           tip: recorder.tip(for: .window)) {
                    Task { await recorder.chooseWindow() }
                }
                ModeButton(mode: .audio, isSelected: recorder.mode == .audio,
                           tip: recorder.tip(for: .audio)) {
                    recorder.chooseAudio()
                }
            }
            .disabled(locked)

            BarDivider()

            Group {
                ToggleButton(onIcon: "speaker.wave.2.fill", offIcon: "speaker.slash.fill",
                             tip: recorder.systemAudioTip, isOn: $recorder.includeSystemAudio)
                ToggleButton(onIcon: "mic.fill", offIcon: "mic.slash.fill",
                             tip: tr("마이크 포함", "Include microphone"), isOn: $recorder.includeMicrophone)

                if recorder.showAdvanced {
                    if isVideoMode {
                        ToggleButton(onIcon: "cursorarrow", offIcon: "cursorarrow.slash",
                                     tip: tr("커서 보이기", "Show cursor"), isOn: $recorder.showCursor)
                            .transition(.scale(scale: 0.5).combined(with: .opacity))
                    }
                    CountdownButton(isOn: $recorder.countdownEnabled)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                    if isVideoMode {
                        qualityMenu
                            .transition(.scale(scale: 0.5).combined(with: .opacity))
                    }
                    settingsMenu
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                }

                AdvancedButton(isOn: $recorder.showAdvanced)
            }
            .disabled(locked)

            BarDivider()

            if recorder.lastFileURL != nil {
                recentMenu
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            }

            RecordButton(isRecording: recorder.isRecording,
                         isBusy: recorder.isBusy || recorder.countdownActive,
                         isReady: recorder.mode != nil,
                         elapsed: recorder.elapsedText) {
                Task { await recorder.toggle() }
            }
            .padding(.leading, 4)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            VisualEffectView(material: .popover)
                .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1))
        )
        .overlay(IntroRing(tick: recorder.introTick, cornerRadius: 17).allowsHitTesting(false))
        .shadow(color: .black.opacity(0.22), radius: 14, y: 5)
        .fixedSize()
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: recorder.mode)
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: recorder.showAdvanced)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: recorder.lastFileURL)
    }

    // MARK: - 알림 (부드럽게 떴다 사라짐)

    @ViewBuilder
    private var noticeView: some View {
        if let notice = recorder.notice {
            HStack(spacing: 8) {
                Image(systemName: notice.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(notice.isError ? Color.orange : Color.green)
                Text(notice.text)
                    .lineLimit(2)
                    .truncationMode(.middle)
                if notice.fileURL != nil {
                    NoticeButton(title: tr("보기", "Show")) { recorder.revealLastFile() }
                    NoticeButton(title: tr("자르기", "Trim")) { recorder.trimLastFile() }
                }
                Button {
                    recorder.dismissNotice()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .font(.system(size: 12))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(VisualEffectView(material: .popover).clipShape(Capsule()))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1)))
            .shadow(color: .black.opacity(0.2), radius: 10, y: 3)
            .fixedSize()
            .transition(.asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.9)),
                removal: .opacity.combined(with: .scale(scale: 0.95))))
            .id(notice.id)
        }
    }

    // MARK: - 메뉴들

    /// 방금 녹화한 파일: 보기 / 앞뒤 자르기
    private var recentMenu: some View {
        Menu {
            Button(tr("Finder에서 보기", "Show in Finder")) { recorder.revealLastFile() }
            Button(tr("앞뒤 자르기…", "Trim…")) { recorder.trimLastFile() }
            Divider()
            Button(tr("저장 폴더 열기", "Open folder")) { recorder.openFolder() }
        } label: {
            Image(systemName: "film.stack")
                .font(.system(size: 17, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .tint(Color.primary)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 43, height: 36)
        .hoverTip(tr("방금 녹화한 파일", "Last recording"))
    }

    private var qualityMenu: some View {
        Menu {
            Picker(tr("해상도", "Resolution"), selection: $recorder.quality) {
                ForEach(OutputQuality.allCases) { q in
                    Text(q.title).tag(q)
                }
            }
            .pickerStyle(.inline)

            Picker(tr("프레임", "Frame rate"), selection: $recorder.fps) {
                Text("30 FPS").tag(30)
                Text("60 FPS").tag(60)
            }
            .pickerStyle(.inline)

            Picker(tr("형식", "Format"), selection: $recorder.videoFormat) {
                ForEach(VideoFormat.allCases) { f in
                    Text(f.title).tag(f)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Text("\(recorder.quality.title) · \(recorder.fps) · \(recorder.videoFormat.short)")
                .font(.system(size: 14, weight: .medium).monospacedDigit())
        }
        .menuStyle(.borderlessButton)
        .tint(Color.primary)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(.horizontal, 8)
        .frame(height: 36)
        .hoverTip(tr("해상도 · 프레임 · 형식", "Resolution · FPS · Format"))
    }

    private var settingsMenu: some View {
        Menu {
            Toggle(tr("시작·종료 효과음", "Start/stop sounds"), isOn: $recorder.playSounds)
            Toggle(tr("녹화 중 툴바 숨기기", "Hide toolbar while recording"), isOn: $recorder.hideWindowWhileRecording)

            Divider()

            Button(tr("앞뒤 자르기…", "Trim a recording…")) { recorder.chooseFileToTrim() }
            Button(tr("저장 폴더 열기", "Open folder")) { recorder.openFolder() }
            Button(tr("단축키 설정…", "Shortcuts…")) { recorder.openSettings() }

            Divider()

            Picker(tr("언어", "Language"), selection: $recorder.language) {
                ForEach(AppLanguage.allCases) { lang in
                    Text(lang.title).tag(lang)
                }
            }

            Divider()

            Button(tr("RecMac 종료", "Quit RecMac")) { NSApp.terminate(nil) }
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 17, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .tint(Color.primary)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 43, height: 36)
        .hoverTip(tr("설정", "Settings"))
    }

    private var displayList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(tr("녹화할 화면", "Display to record"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 10)
            VStack(spacing: 2) {
                ForEach(recorder.displays, id: \.displayID) { display in
                    ListRow(isChecked: recorder.selectedDisplayID == display.displayID) {
                        recorder.selectedDisplayID = display.displayID
                        showDisplayList = false
                    } content: {
                        Image(systemName: "display")
                        Text(recorder.label(for: display))
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 6)
        }
        .padding(.bottom, 8)
        .frame(width: 300)
    }
}

struct FlyValues {
    var sx: CGFloat = 1
    var sy: CGFloat = 1
}

/// 툴바가 나타날 때 테두리를 따라 빨간 빛이 한 바퀴 돈다.
/// SwiftUI가 매 프레임 다시 그리는 대신 Core Animation(GPU)이 직접 움직여서,
/// 툴바가 올라오는 동안이나 다른 화면 갱신이 있어도 끊기지 않는다.
private struct IntroRing: NSViewRepresentable {
    let tick: Int
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> RingView {
        let view = RingView()
        view.cornerRadius = cornerRadius
        view.lastTick = 0
        return view
    }

    func updateNSView(_ view: RingView, context: Context) {
        guard view.lastTick != tick else { return }
        view.lastTick = tick
        if tick > 0 { view.play() }
    }
}

final class RingView: NSView {
    var cornerRadius: CGFloat = 14
    var lastTick = 0
    private let container = CALayer()
    private var segments: [CAShapeLayer] = []
    private var perimeter: CGFloat = 0
    /// (꼬리 길이 비율, 진하기) — 세 겹을 겹쳐 꼬리가 자연스럽게 옅어진다
    private let specs: [(CGFloat, CGFloat)] = [(0.30, 0.14), (0.17, 0.28), (0.07, 0.6)]

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(container)
        container.opacity = 0
        container.shadowColor = NSColor.systemRed.cgColor
        container.shadowOpacity = 0.35
        container.shadowRadius = 4
        container.shadowOffset = .zero
        for (_, alpha) in specs {
            let s = CAShapeLayer()
            s.fillColor = nil
            s.strokeColor = NSColor.systemRed.withAlphaComponent(alpha).cgColor
            s.lineWidth = 1.5
            s.lineCap = .round
            container.addSublayer(s)
            segments.append(s)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        container.frame = bounds
        let rect = bounds.insetBy(dx: 0.75, dy: 0.75)
        let r = max(0, min(cornerRadius - 0.75, rect.height / 2, rect.width / 2))
        let path = CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
        // 둥근 모서리 사각형의 정확한 둘레
        perimeter = 2 * (rect.width + rect.height) - 8 * r + 2 * .pi * r
        for (i, s) in segments.enumerated() {
            let length = specs[i].0 * perimeter
            s.frame = bounds
            s.path = path
            s.lineDashPattern = [NSNumber(value: Double(length)), NSNumber(value: Double(perimeter - length))]
            s.lineDashPhase = length
        }
        CATransaction.commit()
    }

    func play(retries: Int = 3) {
        layoutSubtreeIfNeeded()
        guard perimeter > 1 else {
            if retries > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.play(retries: retries - 1) }
            }
            return
        }
        let duration: CFTimeInterval = 2.8
        let start = CACurrentMediaTime() + 0.35          // 툴바가 다 올라온 뒤 시작
        let ease = CAMediaTimingFunction(controlPoints: 0.35, 0, 0.25, 1)

        for (i, s) in segments.enumerated() {
            let length = specs[i].0 * perimeter
            let run = CABasicAnimation(keyPath: "lineDashPhase")
            run.fromValue = length                       // 머리 = 시작점
            run.toValue = length - perimeter             // 한 바퀴를 같은 속도로
            run.duration = duration
            run.beginTime = start
            run.timingFunction = ease
            run.fillMode = .backwards
            s.removeAllAnimations()
            s.add(run, forKey: "run")
        }

        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 1, 1, 0]
        fade.keyTimes = [0, 0.2, 0.62, 1]
        fade.duration = duration
        fade.beginTime = start
        fade.timingFunctions = [CAMediaTimingFunction(name: .easeOut),
                                CAMediaTimingFunction(name: .linear),
                                CAMediaTimingFunction(name: .easeInEaseOut)]
        container.removeAllAnimations()
        container.add(fade, forKey: "fade")
    }
}

private struct NoticeButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.primary.opacity(0.1)))
    }
}

/// 고급 옵션 펼치기/접기
private struct AdvancedButton: View {
    @Binding var isOn: Bool
    @State private var hovering = false

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(isOn ? Color.primary : Color.secondary)
                .frame(width: 41, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(isOn ? 0.12 : (hovering ? 0.07 : 0)))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
        .hoverTip(isOn ? tr("고급 옵션 접기", "Hide advanced") : tr("고급 옵션", "Advanced"))
    }
}

// MARK: - 반투명 배경

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
    }
}

// MARK: - 호버 설명 말풍선

private struct HoverTip: ViewModifier {
    let text: String
    @State private var show = false
    @State private var pending: DispatchWorkItem?

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                pending?.cancel()
                if inside {
                    let work = DispatchWorkItem {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { show = true }
                    }
                    pending = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
                } else {
                    withAnimation(.easeOut(duration: 0.12)) { show = false }
                }
            }
            .overlay(alignment: .top) {
                if show {
                    Text(text)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(VisualEffectView(material: .toolTip).clipShape(Capsule()))
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12)))
                        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                        .fixedSize()
                        .offset(y: -42)
                        .transition(.opacity.combined(with: .offset(y: 4)))
                        .allowsHitTesting(false)
                }
            }
    }
}

extension View {
    func hoverTip(_ text: String) -> some View { modifier(HoverTip(text: text)) }
}

// MARK: - 컴포넌트

private struct BarDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(width: 1, height: 22)
            .padding(.horizontal, 5)
    }
}

private struct CloseButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 19))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(hovering ? Color.primary : Color.secondary)
                .frame(width: 34, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .hoverTip(tr("메뉴 막대로 접기", "Hide to menu bar"))
    }
}

/// 스크린샷 툴바처럼 아이콘만 있는 방식 버튼. 고르면 배경이 깔리고 아이콘이 빨개진다.
private struct ModeButton: View {
    let mode: CaptureMode
    let isSelected: Bool
    let tip: String
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: mode.icon)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(isSelected ? Color.brand : Color.primary)
                .symbolEffect(.bounce, value: isSelected)
                .frame(width: 48, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(isSelected ? 0.13 : (hovering ? 0.07 : 0)))
                )
                .opacity(isEnabled ? 1 : 0.4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isSelected)
        .hoverTip(tip)
    }
}

private struct ToggleButton: View {
    let onIcon: String
    let offIcon: String
    let tip: String
    @Binding var isOn: Bool
    @State private var hovering = false

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) { isOn.toggle() }
        } label: {
            Image(systemName: isOn ? onIcon : offIcon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(isOn ? Color.primary : Color.secondary.opacity(0.7))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 41, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(hovering ? 0.07 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
        .hoverTip(tip)
    }
}

/// 꺼짐: 흐린 타이머 아이콘만 / 켜짐: 밝은 아이콘 + 작은 빨간 "3" 배지
private struct CountdownButton: View {
    @Binding var isOn: Bool
    @State private var hovering = false

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) { isOn.toggle() }
        } label: {
            Image(systemName: "timer")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(isOn ? Color.primary : Color.secondary.opacity(0.7))
                .frame(width: 41, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(hovering ? 0.07 : 0))
                )
                .overlay(alignment: .bottomTrailing) {
                    if isOn {
                        Text("3")
                            .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color(nsColor: .windowBackgroundColor))
                            .frame(width: 14, height: 14)
                            .background(Circle().fill(Color.primary.opacity(0.85)))
                            .offset(x: -4, y: -2)
                            .transition(.scale(scale: 0.2).combined(with: .opacity))
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
        .hoverTip(isOn ? tr("3초 뒤 시작", "Start after 3s") : tr("3초 카운트다운", "3s countdown"))
    }
}

private struct ListRow<Content: View>: View {
    let isChecked: Bool
    let action: () -> Void
    @ViewBuilder let content: () -> Content
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                content()
                Spacer()
                if isChecked {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.brand)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(hovering ? Color.primary.opacity(0.08) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// 스크린샷 툴바의 "Capture" 자리에 있는 빨간 녹화 버튼
private struct RecordButton: View {
    let isRecording: Bool
    let isBusy: Bool
    let isReady: Bool
    let elapsed: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else if isRecording {
                    RoundedRectangle(cornerRadius: 2)
                        .frame(width: 11, height: 11)
                    Text(elapsed)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                } else {
                    Circle()
                        .frame(width: 11, height: 11)
                    Text(tr("녹화", "Record"))
                }
            }
            .font(.system(size: 15.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(minWidth: 76)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.brand.opacity(isReady || isRecording ? (hovering ? 0.88 : 1) : 0.35))
            )
            .contentShape(Rectangle())
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isRecording)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .onHover { hovering = $0 }
        .keyboardShortcut("r", modifiers: .command)
        .hoverTip(isRecording ? tr("정지 ⌘R", "Stop ⌘R") : (isReady ? tr("녹화 시작 ⌘R", "Record ⌘R") : tr("녹화 방식을 먼저 고르세요", "Choose a mode first")))
    }
}
