import { DAY_SECONDS, SEGMENT_SECONDS, durationLabel, hhmm, positionOf, sameDay, startOfDay } from "../lib/argos";

/** A linha do tempo de um dia: onde há gravação e onde houve movimento.
 *
 *  É o controle, não um enfeite: tem um cursor que anda com o vídeo, e clicar
 *  num horário salta para aquele segundo. Sem isso seriam dois controles
 *  falando do mesmo instante sem se falarem — a barra do player e esta faixa. */
export default function Timeline({ day, episodes, current, playhead, onSeek, selecao, onSelecionar }) {
  const isToday = sameDay(day.date, new Date());

  const instanteEm = (event) => {
    const rect = event.currentTarget.getBoundingClientRect();
    const frac = (event.clientX - rect.left) / rect.width;
    return new Date(+startOfDay(day.date) + frac * DAY_SECONDS * 1000);
  };

  const handle = (event) => {
    // Arrastar com Shift marca um intervalo para exportar; clique simples
    // continua sendo navegar, que é o uso de longe mais comum.
    if (event.shiftKey && onSelecionar) {
      onSelecionar(instanteEm(event));
      return;
    }
    onSeek(instanteEm(event));
  };

  return (
    <div className="select-none">
      {/* Régua de três em três horas: densidade suficiente para situar, sem
          virar grade. */}
      <div className="relative h-4 text-[10px] tabular-nums text-neutral-500">
        {[0, 3, 6, 9, 12, 15, 18, 21, 24].map((h) => (
          <span
            key={h}
            className="absolute"
            style={h === 24 ? { right: 0 } : { left: `${(h / 24) * 100}%` }}
          >
            {h}h
          </span>
        ))}
      </div>

      <div
        onClick={handle}
        className="relative h-11 cursor-pointer overflow-hidden rounded-md border border-white/10 bg-trough sm:h-14"
      >
        {/* Divisões de hora: dão escala sem pedir atenção. */}
        {Array.from({ length: 23 }, (_, i) => i + 1).map((h) => (
          <div
            key={h}
            className={`absolute inset-y-0 w-px ${h % 6 === 0 ? "bg-black/30" : "bg-black/15"}`}
            style={{ left: `${(h / 24) * 100}%` }}
          />
        ))}

        {/* Movimento: a pista de cima, em âmbar, que é a que se lê. */}
        <div className="absolute inset-x-0 top-0 h-[68%]">
          {episodes.map((ep) => (
            <div
              key={+ep.start}
              title={`${hhmm(ep.start)} · movimento por ${durationLabel((ep.end - ep.start) / 1000)}`}
              className="absolute inset-y-0 rounded-sm bg-motion"
              style={{
                left: `${positionOf(ep.start, day)}%`,
                // Mínimo visível: um episódio de segundos num dia de 24h
                // desaparece, e desaparecer é pior que exagerar.
                width: `max(3px, ${((ep.end - ep.start) / 1000 / DAY_SECONDS) * 100}%)`,
              }}
            />
          ))}
        </div>

        {/* Gravação existente: a pista fina embaixo, azul e discreta. */}
        <div className="absolute inset-x-0 bottom-0 h-[26%]">
          {day.segments.map((s) => (
            <div
              key={s.path}
              className={`absolute inset-y-0 rounded-[2px] ${
                s === current ? "bg-white" : "bg-rec/60"
              }`}
              style={{
                left: `${positionOf(s.at, day)}%`,
                width: `max(2px, ${(SEGMENT_SECONDS / DAY_SECONDS) * 100}%)`,
              }}
            />
          ))}
        </div>

        {isToday && (
          <div
            className="absolute inset-y-0 w-[1.5px] bg-live"
            style={{ left: `${positionOf(new Date(), day)}%` }}
          />
        )}

        {/* O cursor: a ponte entre a faixa e a imagem. */}
        {playhead && sameDay(playhead, day.date) && (
          <div
            className="absolute inset-y-0 w-0.5 bg-white shadow-[0_0_4px_rgba(0,0,0,.8)]"
            style={{ left: `${positionOf(playhead, day)}%` }}
          >
            <span className="absolute -left-[2.5px] -top-[3px] size-[7px] rounded-full bg-white" />
          </div>
        )}
      </div>
    </div>
  );
}
