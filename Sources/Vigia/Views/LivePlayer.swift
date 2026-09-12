import SwiftUI
import AVKit

/// A imagem ao vivo, sem controles de reprodução.
///
/// O `VideoPlayer` do SwiftUI traz barra de progresso, avançar e retroceder —
/// todos sem sentido num fluxo que não tem fim nem começo. Aqui usamos a camada
/// de vídeo direta, que mostra só a imagem.
///
/// O problema mais importante que esta view resolve, porém, não é visual: um
/// player de HLS ao vivo escorrega para trás. Cada engasgo de rede acumula
/// atraso, e em minutos a "imagem ao vivo" está mostrando o passado — ou
/// congela, quando o servidor já apagou os segmentos que o player ainda
/// esperava. Por isso ele se vigia e volta para a borda quando fica para trás.
struct LivePlayer: NSViewRepresentable {
    let url: URL
    /// Atraso tolerado antes de pular para o presente.
    var maximumDrift: TimeInterval = 8

    func makeNSView(context: Context) -> LiveVideoView {
        let view = LiveVideoView()
        view.start(url: url, maximumDrift: maximumDrift)
        return view
    }

    func updateNSView(_ view: LiveVideoView, context: Context) {
        view.start(url: url, maximumDrift: maximumDrift)
    }

    static func dismantleNSView(_ view: LiveVideoView, coordinator: ()) {
        view.stop()
    }
}

final class LiveVideoView: NSView {
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var watchdog: Timer?
    private var currentURL: URL?
    private var lastAdvance = Date()
    private var lastTime: CMTime = .zero

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) { nil }

    func start(url: URL, maximumDrift: TimeInterval) {
        guard currentURL != url else { return }
        stop()
        currentURL = url

        let item = AVPlayerItem(url: url)
        // Buffer curto: num fluxo ao vivo, buffer grande é atraso garantido.
        item.preferredForwardBufferDuration = 2

        let player = AVPlayer(playerItem: item)
        // Deixa a reprodução começar assim que houver dados, em vez de esperar
        // encher o buffer — o que atrasaria o ao vivo desde o primeiro quadro.
        player.automaticallyWaitsToMinimizeStalling = false

        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspect
        layer.frame = bounds
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        self.layer?.addSublayer(layer)

        self.player = player
        self.playerLayer = layer
        player.play()

        startWatchdog(maximumDrift: maximumDrift)
    }

    func stop() {
        watchdog?.invalidate()
        watchdog = nil
        player?.pause()
        player = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        currentURL = nil
    }

    /// Verifica de tempos em tempos se a imagem ainda anda e se está no presente.
    private func startWatchdog(maximumDrift: TimeInterval) {
        lastAdvance = Date()
        lastTime = .zero

        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            guard let self, let player, let item = player.currentItem else { return }

            let now = item.currentTime()
            if now != lastTime {
                lastTime = now
                lastAdvance = Date()
            }

            // O fim do que o servidor publicou: a borda do ao vivo.
            guard let edge = item.seekableTimeRanges.last?.timeRangeValue else { return }
            let live = CMTimeAdd(edge.start, edge.duration)
            let drift = CMTimeGetSeconds(CMTimeSubtract(live, now))

            let stalled = Date().timeIntervalSince(lastAdvance) > 5
            if stalled || drift > maximumDrift {
                // Saltar para perto da borda, e não exatamente nela: colar no
                // último instante publicado faz o player engasgar a cada
                // segmento que ainda está sendo escrito.
                let target = CMTimeSubtract(live, CMTime(seconds: 1.5, preferredTimescale: 600))
                player.seek(to: target, toleranceBefore: .positiveInfinity, toleranceAfter: .zero) { _ in
                    player.play()
                }
            }

            if player.timeControlStatus == .paused { player.play() }
        }
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
    }
}
