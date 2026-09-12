import Foundation
import AVFoundation
import CoreVideo
import Observation

/// Uma região da imagem onde alguma coisa se mexeu.
///
/// Coordenadas normalizadas (0–1) com origem no canto superior esquerdo, para
/// que a caixa sirva em qualquer tamanho de janela sem recalcular nada.
struct MotionBox: Identifiable, Hashable, Sendable {
    let id: Int
    let rect: CGRect
    /// Quanto da região mudou, de 0 a 1 — usado para apagar ruído fraco.
    let intensity: Double
}

/// Acha onde o movimento aconteceu, comparando quadros vizinhos.
///
/// A câmera sabe *que* houve movimento e a que horas, mas o evento que ela
/// publica não diz onde na cena — e o grid que algumas firmwares mandam é
/// grosseiro demais para desenhar em cima da imagem. Comparar quadros aqui
/// resolve isso sem servidor, sem modelo treinado e sem custo de rede: o que
/// mudou de um quadro para o outro é, por definição, o que se mexeu.
///
/// Detectar pessoas em vez de movimento daria caixas mais bonitas, mas erraria
/// justamente o caso que importa numa câmera de rua — um carro entrando, um
/// portão abrindo, um animal — que não é pessoa nenhuma.
@MainActor
@Observable
final class MotionVision {
    private(set) var boxes: [MotionBox] = []
    var isEnabled = true {
        didSet { if !isEnabled { boxes = [] } }
    }

    /// Resolução da análise. Reduzir a imagem antes de comparar é o que torna
    /// isto barato: 64×36 células bastam para enquadrar um corpo numa cena de
    /// rua, e custam milhares de vezes menos que 1920×1080.
    private let cols = 64
    private let rows = 36

    /// Diferença de brilho, por célula, que conta como mudança.
    ///
    /// Medido nesta câmera: com a cena parada o ruído do sensor fica em 2 a 3,
    /// com picos raros perto de 17; um corpo atravessando muda dezenas. 12
    /// passa longe do ruído e ainda pega movimento discreto.
    private let threshold = 12

    /// Quantas células precisam mudar para a cena valer análise. Sem esse piso,
    /// a compressão de vídeo sozinha acende células soltas o tempo todo.
    private let minimumCells = 6

    private var output: AVPlayerItemVideoOutput?
    private var timer: Timer?
    private var previous: [UInt8]?
    private weak var player: AVPlayer?

    // MARK: Ciclo de vida

    func attach(to player: AVPlayer) {
        detach()
        self.player = player

        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            // Pedir a imagem já reduzida deixa a conversão de cor com o
            // decodificador, que faz isso em hardware.
            kCVPixelBufferWidthKey as String: cols * 4,
            kCVPixelBufferHeightKey as String: rows * 4,
        ])
        player.currentItem?.add(output)
        self.output = output

        // 8 vezes por segundo: rápido o bastante para a caixa acompanhar quem
        // anda, devagar o bastante para não disputar CPU com a decodificação.
        let timer = Timer(timeInterval: 1.0 / 8.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func detach() {
        timer?.invalidate()
        timer = nil
        if let output, let item = player?.currentItem {
            item.remove(output)
        }
        output = nil
        previous = nil
        boxes = []
        player = nil
    }

    // MARK: Análise

    private func tick() {
        guard isEnabled, let output, let player else { return }

        let time = player.currentTime()
        guard output.hasNewPixelBuffer(forItemTime: time),
              let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil),
              let luma = sample(buffer)
        else { return }
        defer { previous = luma }

        guard let previous, previous.count == luma.count else { return }

        // Células que mudaram acima do limiar.
        var changed = [Bool](repeating: false, count: luma.count)
        var total = 0
        for index in luma.indices {
            let delta = abs(Int(luma[index]) - Int(previous[index]))
            if delta > threshold {
                changed[index] = true
                total += 1
            }
        }

        guard total >= minimumCells else {
            // Some devagar: apagar a caixa no primeiro quadro parado faria ela
            // piscar a cada passo de quem anda.
            if !boxes.isEmpty { boxes = [] }
            return
        }

        boxes = group(changed, total: total)
    }

    /// Reduz o quadro a uma grade de brilho.
    ///
    /// Brilho e não cor: mudança de cor sem mudança de luz é quase sempre
    /// compressão, não movimento.
    private func sample(_ buffer: CVPixelBuffer) -> [UInt8]? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        guard width >= cols, height >= rows else { return nil }

        let pixels = base.assumingMemoryBound(to: UInt8.self)
        var result = [UInt8](repeating: 0, count: cols * rows)

        for row in 0..<rows {
            let y = row * height / rows
            let line = pixels.advanced(by: y * stride)
            for col in 0..<cols {
                let x = col * width / cols
                let pixel = line.advanced(by: x * 4)
                // BGRA, com os pesos padrão de luminância.
                let blue = Int(pixel[0]), green = Int(pixel[1]), red = Int(pixel[2])
                result[row * cols + col] = UInt8((red * 77 + green * 150 + blue * 29) >> 8)
            }
        }
        return result
    }

    /// Junta células vizinhas numa caixa só.
    ///
    /// Uma pessoa andando acende dezenas de células espalhadas; desenhar uma
    /// caixa por célula seria confete. A varredura em largura agrupa o que se
    /// toca, que é o que o olho já lê como "uma coisa".
    private func group(_ changed: [Bool], total: Int) -> [MotionBox] {
        var seen = [Bool](repeating: false, count: changed.count)
        var result: [MotionBox] = []
        var identifier = 0

        for start in changed.indices where changed[start] && !seen[start] {
            var queue = [start]
            seen[start] = true
            var minCol = cols, maxCol = 0, minRow = rows, maxRow = 0
            var count = 0

            while let index = queue.popLast() {
                let row = index / cols, col = index % cols
                count += 1
                minCol = min(minCol, col); maxCol = max(maxCol, col)
                minRow = min(minRow, row); maxRow = max(maxRow, row)

                // Vizinhança de 8, com uma folga de uma célula: partes de um
                // mesmo corpo costumam ficar separadas por uma célula parada.
                for dr in -2...2 {
                    for dc in -2...2 {
                        let r = row + dr, c = col + dc
                        guard r >= 0, r < rows, c >= 0, c < cols else { continue }
                        let neighbour = r * cols + c
                        if changed[neighbour] && !seen[neighbour] {
                            seen[neighbour] = true
                            queue.append(neighbour)
                        }
                    }
                }
            }

            // Regiões minúsculas são ruído; regiões que cobrem quase a tela
            // inteira são mudança de luz, não movimento — as duas se descartam.
            let area = Double((maxCol - minCol + 1) * (maxRow - minRow + 1))
            guard count >= 4, area < Double(cols * rows) * 0.75 else { continue }

            identifier += 1
            // Uma folga em volta para a caixa não cortar as bordas do corpo.
            let padX = 1.0 / Double(cols), padY = 1.0 / Double(rows)
            let rect = CGRect(
                x: max(0, Double(minCol) / Double(cols) - padX),
                y: max(0, Double(minRow) / Double(rows) - padY),
                width: min(1, Double(maxCol - minCol + 1) / Double(cols) + padX * 2),
                height: min(1, Double(maxRow - minRow + 1) / Double(rows) + padY * 2))

            result.append(MotionBox(id: identifier, rect: rect,
                                    intensity: Double(count) / area))
        }

        // As maiores primeiro, e no máximo quatro: mais que isso vira poluição
        // sobre a imagem em vez de informação.
        return Array(result.sorted { $0.rect.area > $1.rect.area }.prefix(4))
    }
}

private extension CGRect {
    var area: CGFloat { width * height }
}
