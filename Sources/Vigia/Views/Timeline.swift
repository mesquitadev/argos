import SwiftUI

/// A linha do tempo de um dia: onde há gravação e onde houve movimento.
///
/// A leitura que importa não é "quantos arquivos existem", e sim "o que
/// aconteceu e quando". A faixa de gravação é o fundo, contínuo e calmo; os
/// episódios de movimento são o que salta. Assim se acha o trecho certo sem
/// abrir arquivo por arquivo.
struct Timeline: View {
    let day: RecordingDay
    let episodes: [MotionEpisode]
    let selected: Recording?
    let onSelect: (Recording) -> Void

    /// Onde o cursor está, para mostrar a hora exata sob o ponteiro.
    @State private var hoverX: CGFloat?

    private var dayStart: Date { Calendar.current.startOfDay(for: day.date) }
    private let secondsInDay: TimeInterval = 86_400

    /// Alturas das duas pistas. A de movimento é maior porque é a que se lê.
    private let motionHeight: CGFloat = 34
    private let recordHeight: CGFloat = 12
    private let gap: CGFloat = 3

    private var trackHeight: CGFloat { motionHeight + gap + recordHeight }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ruler
            track
            legend
        }
    }

    // MARK: Régua

    /// Horas de três em três: densidade suficiente para situar, sem virar grade.
    private var ruler: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .topLeading) {
                ForEach(Array(stride(from: 0, through: 24, by: 3)), id: \.self) { hour in
                    let x = width * CGFloat(hour) / 24
                    Text(hour == 24 ? "24h" : "\(hour)h")
                        .font(Theme.numeric(10))
                        .foregroundStyle(Theme.tertiaryText)
                        // A última etiqueta ancora à direita para não vazar.
                        .offset(x: hour == 24 ? x - 22 : x + 3)
                }
                // A hora sob o cursor, que substitui a régua enquanto se navega.
                if let hoverX, width > 0 {
                    let fraction = max(0, min(1, hoverX / width))
                    Text(timeLabel(fraction))
                        .font(Theme.numeric(10, .medium))
                        .foregroundStyle(Theme.canvas)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Theme.primaryText, in: RoundedRectangle(cornerRadius: 3))
                        .offset(x: min(max(hoverX - 22, 0), width - 44))
                }
            }
        }
        .frame(height: 14)
    }

    // MARK: Trilho

    private var track: some View {
        GeometryReader { geometry in
            let width = geometry.size.width

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 5).fill(Theme.trough)

                // Divisões de hora dentro do trilho: dão escala sem pedir atenção.
                ForEach(1..<24) { hour in
                    Rectangle()
                        .fill(Color.black.opacity(hour % 6 == 0 ? 0.28 : 0.12))
                        .frame(width: 1)
                        .offset(x: width * CGFloat(hour) / 24)
                }

                // Episódios de movimento: a pista de cima, em âmbar.
                ForEach(episodes) { episode in
                    let x = offset(episode.start, width: width)
                    // Mínimo de 3px: um episódio de segundos num dia de 24h
                    // desaparece, e desaparecer é pior que exagerar.
                    let w = max(3, width * CGFloat(episode.duration / secondsInDay))
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Theme.motion)
                        .frame(width: w, height: motionHeight)
                        .offset(x: x)
                        .help("\(episode.start.formatted(date: .omitted, time: .shortened)) · movimento por \(episode.durationLabel)")
                }

                // Gravação existente: a pista fina embaixo, azul e discreta.
                ForEach(day.recordings) { recording in
                    if let start = recording.startedAt {
                        let isSelected = recording == selected
                        RoundedRectangle(cornerRadius: 1)
                            .fill(isSelected ? Theme.primaryText : Theme.recording.opacity(0.55))
                            .frame(width: max(2, width * CGFloat(300 / secondsInDay)),
                                   height: recordHeight)
                            .offset(x: offset(start, width: width), y: motionHeight + gap)
                    }
                }

                // Marca do agora, só no dia de hoje.
                if Calendar.current.isDateInToday(day.date) {
                    let x = offset(.now, width: width)
                    Rectangle()
                        .fill(Theme.live)
                        .frame(width: 1.5, height: trackHeight)
                        .offset(x: x)
                }

                // Linha de cursor, para ligar o ponteiro à hora na régua.
                if let hoverX {
                    Rectangle()
                        .fill(Theme.primaryText.opacity(0.5))
                        .frame(width: 1, height: trackHeight)
                        .offset(x: hoverX)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.hairline))
            .contentShape(Rectangle())
            // Clicar em qualquer ponto vai para a gravação daquele instante,
            // em vez de exigir acerto na faixa fina de cinco minutos.
            .onTapGesture { location in
                seek(fraction: location.x / max(width, 1))
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let point): hoverX = point.x
                case .ended: hoverX = nil
                }
            }
        }
        .frame(height: trackHeight)
    }

    // MARK: Legenda

    private var legend: some View {
        HStack(spacing: 14) {
            swatch(Theme.motion, "Movimento")
            swatch(Theme.recording.opacity(0.7), "Gravado")
            if Calendar.current.isDateInToday(day.date) {
                swatch(Theme.live, "Agora")
            }
            Spacer()
            Text("Clique na linha para abrir o trecho")
                .font(.system(size: 10))
                .foregroundStyle(Theme.tertiaryText)
        }
    }

    private func swatch(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 9, height: 9)
            Text(text).font(.system(size: 10)).foregroundStyle(Theme.secondaryText)
        }
    }

    // MARK: Cálculos

    private func offset(_ date: Date, width: CGFloat) -> CGFloat {
        let seconds = date.timeIntervalSince(dayStart)
        return width * CGFloat(max(0, min(secondsInDay, seconds)) / secondsInDay)
    }

    private func timeLabel(_ fraction: CGFloat) -> String {
        let date = dayStart.addingTimeInterval(secondsInDay * TimeInterval(fraction))
        return date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute())
    }

    /// A gravação que cobre aquele instante, ou a anterior mais próxima.
    private func seek(fraction: CGFloat) {
        let target = dayStart.addingTimeInterval(secondsInDay * TimeInterval(max(0, min(1, fraction))))
        let candidates = day.recordings.compactMap { recording -> (Recording, Date)? in
            guard let start = recording.startedAt else { return nil }
            return (recording, start)
        }
        guard let best = candidates.min(by: {
            abs($0.1.timeIntervalSince(target)) < abs($1.1.timeIntervalSince(target))
        }) else { return }
        onSelect(best.0)
    }
}
