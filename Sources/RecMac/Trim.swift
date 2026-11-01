import AppKit
import AVKit
import AVFoundation
import UniformTypeIdentifiers

enum TrimResult {
    case saved(URL), cancelled, failed
}

/// QuickTime처럼 노란 손잡이로 앞뒤를 잘라 "(편집)" 파일로 저장한다. 원본은 그대로 둔다.
@MainActor
final class TrimController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var completion: ((TrimResult) -> Void)?

    func open(url: URL, completion: @escaping (TrimResult) -> Void) {
        close()
        self.completion = completion

        let player = AVPlayer(url: url)
        let playerView = AVPlayerView()
        playerView.player = player
        playerView.controlsStyle = .inline
        playerView.showsFullScreenToggleButton = false

        let isAudio = Self.isAudioFile(url)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: isAudio ? 160 : 540),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = tr("앞뒤 자르기 — ", "Trim — ") + url.lastPathComponent
        window.isReleasedWhenClosed = false
        window.contentView = playerView
        window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window

        beginTrimming(playerView: playerView, player: player, url: url, tries: 0)
    }

    /// 영상이 준비될 때까지 잠깐 기다렸다가 자르기 모드를 연다
    private func beginTrimming(playerView: AVPlayerView, player: AVPlayer, url: URL, tries: Int) {
        guard window != nil else { return }
        guard playerView.canBeginTrimming else {
            if tries < 30 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    MainActor.assumeIsolated {
                        self?.beginTrimming(playerView: playerView, player: player, url: url, tries: tries + 1)
                    }
                }
            } else {
                finish(.failed)
            }
            return
        }
        playerView.beginTrimming { [weak self] result in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard result == .okButton, let item = player.currentItem else {
                    self.finish(.cancelled)
                    return
                }
                let start = item.reversePlaybackEndTime.isValid ? item.reversePlaybackEndTime : .zero
                let end = item.forwardPlaybackEndTime.isValid ? item.forwardPlaybackEndTime : item.duration
                player.pause()
                Task { @MainActor in
                    do {
                        let out = try await self.export(url: url, start: start, end: end)
                        self.finish(.saved(out))
                    } catch {
                        self.finish(.failed)
                    }
                }
            }
        }
    }

    private func export(url: URL, start: CMTime, end: CMTime) async throws -> URL {
        let asset = AVURLAsset(url: url)
        let isAudio = Self.isAudioFile(url)
        let preset = isAudio ? AVAssetExportPresetAppleM4A : AVAssetExportPresetHighestQuality
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw NSError(domain: "RecMac", code: 1)
        }
        session.timeRange = CMTimeRange(start: start, end: end)
        let out = uniqueURL(for: url)
        try await session.export(to: out, as: isAudio ? .m4a : (out.pathExtension == "mov" ? .mov : .mp4))
        return out
    }

    private func uniqueURL(for url: URL) -> URL {
        let folder = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent + tr(" (편집)", " (trimmed)")
        let ext = Self.isAudioFile(url) ? "m4a" : (url.pathExtension.lowercased() == "mov" ? "mov" : "mp4")
        var candidate = folder.appendingPathComponent("\(base).\(ext)")
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base) \(n).\(ext)")
            n += 1
        }
        return candidate
    }

    static func isAudioFile(_ url: URL) -> Bool {
        let type = UTType(filenameExtension: url.pathExtension.lowercased())
        return type?.conforms(to: .audio) == true
    }

    private func finish(_ result: TrimResult) {
        let done = completion
        completion = nil
        close()
        done?(result)
    }

    private func close() {
        if let playerView = window?.contentView as? AVPlayerView {
            playerView.player?.pause()
        }
        window?.delegate = nil
        window?.orderOut(nil)
        window = nil
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            let done = completion
            completion = nil
            window = nil
            done?(.cancelled)
        }
    }
}
