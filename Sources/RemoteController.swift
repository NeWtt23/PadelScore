import AVFoundation
import MediaPlayer
import UserNotifications

/// Hace que la app sea la "reproductora de música" activa, para recibir los
/// botones de música del reloj y mostrar el marcador como título de la canción.
final class RemoteController: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published private(set) var active = false
    @Published var notificationsOn: Bool {
        didSet { UserDefaults.standard.set(notificationsOn, forKey: "notificationsOn") }
    }

    private let scorer: PadelScorer
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var lastRemoteEvent = Date.distantPast

    init(scorer: PadelScorer) {
        self.scorer = scorer
        self.notificationsOn = UserDefaults.standard.object(forKey: "notificationsOn") as? Bool ?? true
        super.init()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        UNUserNotificationCenter.current().delegate = self
        setupRemoteCommands()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }

    // MARK: - Encender / apagar

    func start() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            try startSilence()
            active = true
            updateNowPlaying()
        } catch {
            print("Error de audio: \(error)")
        }
    }

    func stop() {
        player.stop()
        engine.stop()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        active = false
    }

    private func startSilence() throws {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100) else { return }
        buffer.frameLength = 44_100
        if let data = buffer.floatChannelData {
            for i in 0..<Int(buffer.frameLength) { data[0][i] = 0 }
        }
        if !engine.isRunning { try engine.start() }
        player.stop()
        player.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
        player.play()
    }

    // MARK: - Acciones del marcador

    func addPoint(_ team: Team) {
        scorer.point(for: team)
        refresh()
    }

    func undo() {
        scorer.undo()
        refresh()
    }

    func reset() {
        scorer.reset()
        refresh()
    }

    private func refresh() {
        guard active else { return }
        updateNowPlaying()
        notifyWatch()
    }

    // MARK: - Botones del reloj

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.fromWatch { $0.addPoint(.us) }
            return .success
        }

        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.fromWatch { $0.addPoint(.them) }
            return .success
        }

        for command in [center.togglePlayPauseCommand, center.playCommand, center.pauseCommand] {
            command.isEnabled = true
            command.addTarget { [weak self] _ in
                self?.fromWatch { $0.undo() }
                return .success
            }
        }

        center.skipForwardCommand.isEnabled = false
        center.skipBackwardCommand.isEnabled = false
        center.changePlaybackPositionCommand.isEnabled = false
    }

    /// Ignora toques repetidos muy seguidos (evita puntos dobles).
    private func fromWatch(_ action: @escaping (RemoteController) -> Void) {
        DispatchQueue.main.async {
            let now = Date()
            guard now.timeIntervalSince(self.lastRemoteEvent) > 0.4 else { return }
            self.lastRemoteEvent = now
            action(self)
        }
    }

    // MARK: - Lo que ve el reloj

    private func updateNowPlaying() {
        let info: [String: Any] = [
            MPMediaItemPropertyTitle: scorer.summary,
            MPMediaItemPropertyArtist: "Sig.=Nosotros · Ant.=Ellos · Pausa=Deshacer",
            MPMediaItemPropertyAlbumTitle: "Marcador de pádel",
            MPNowPlayingInfoPropertyPlaybackRate: 1.0
        ]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func notifyWatch() {
        guard notificationsOn else { return }
        let center = UNUserNotificationCenter.current()
        center.removeAllDeliveredNotifications()
        let content = UNMutableNotificationContent()
        content.title = "Pádel"
        content.body = scorer.summary
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request, withCompletionHandler: nil)
    }

    // Mostrar la notificación aunque la app esté abierta
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }

    // Después de una llamada u otra interrupción, retomar el audio silencioso
    @objc private func handleInterruption(_ note: Notification) {
        guard active,
              let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw),
              type == .ended else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        try? startSilence()
        updateNowPlaying()
    }
}
