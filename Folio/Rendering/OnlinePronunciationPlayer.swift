import Foundation
import Observation
import AVFoundation
import FolioCore

@MainActor @Observable
final class OnlinePronunciationPlayer {
    private(set) var isLoading = false
    private(set) var error: FolioMessage?
    private var player: AVPlayer?
    private var observation: NSKeyValueObservation?
    private var timeoutTask: Task<Void, Never>?
    private var notifications: [any NSObjectProtocol] = []
    private var requestID = UUID()

    func play(_ url: URL) {
        stop()
        guard url.scheme?.lowercased() == "https", url.host != nil else {
            error = FolioMessage("This pronunciation link isn’t available.")
            return
        }
        error = nil
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            self.error = FolioMessage("Couldn’t start pronunciation playback. Please try again.")
            return
        }
        isLoading = true
        let current = requestID
        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)
        observation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            let status = item.status.rawValue
            Task { @MainActor [weak self] in
                guard let self, self.requestID == current else { return }
                if status == AVPlayerItem.Status.failed.rawValue {
                    self.stop()
                    self.error = FolioMessage("Couldn’t play this pronunciation. Check your connection and Youdao audio access, then try again.")
                } else if status == AVPlayerItem.Status.readyToPlay.rawValue {
                    self.isLoading = false
                    self.player?.play()
                }
            }
        }
        notifications = [
            NotificationCenter.default.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.requestID == current else { return }
                    self.stop()
                    self.error = FolioMessage("Pronunciation playback stopped. Check your connection and try again.")
                }
            },
            NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.requestID == current else { return }
                    self.stop()
                }
            }
        ]
        timeoutTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
            guard let self, self.requestID == current, self.isLoading else { return }
            self.stop()
            self.error = FolioMessage("Pronunciation took too long to load. Check your connection and try again.")
        }
    }

    func stop() {
        error = nil
        let hadPlayer = player != nil
        requestID = UUID()
        isLoading = false
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        observation?.invalidate()
        observation = nil
        player = nil
        notifications.forEach { NotificationCenter.default.removeObserver($0) }
        notifications = []
        timeoutTask?.cancel()
        timeoutTask = nil
        if hadPlayer { try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation]) }
    }

}
