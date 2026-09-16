import { useCallback, useEffect, useRef, useState } from "react";
import DayRail from "./DayRail";
import EpisodeList from "./EpisodeList";
import Timeline from "./Timeline";
import { defaultSegment, episodes as episodesOf, hhmmss, locate } from "../lib/vigia";

export default function RecordingsView({ days, events, day, onPickDay }) {
  const video = useRef(null);
  const [current, setCurrent] = useState(null);
  const [playhead, setPlayhead] = useState(null);
  const pending = useRef(0);

  const eps = day ? episodesOf(events, day.date) : [];

  // Ao trocar de dia, abre o trecho mais recente que se pode assistir.
  useEffect(() => {
    if (!day) return;
    pending.current = 0;
    setCurrent(defaultSegment(day));
  }, [day]);

  // Troca a fonte do vídeo e aplica o salto pendente assim que houver duração:
  // um `seek` antes do arquivo carregar é simplesmente ignorado.
  useEffect(() => {
    const el = video.current;
    if (!el || !current) return;
    el.src = `/recordings/${current.path}`;
    const onReady = () => {
      if (pending.current > 0) el.currentTime = pending.current;
      pending.current = 0;
      el.play().catch(() => {});
    };
    el.addEventListener("loadedmetadata", onReady, { once: true });
    return () => el.removeEventListener("loadedmetadata", onReady);
  }, [current]);

  /** Vai para um instante do dia, atravessando a fronteira entre arquivos. */
  const seek = useCallback(
    (target) => {
      const found = locate(day, target);
      if (!found) return;
      if (found.segment === current) {
        video.current.currentTime = found.offset;
        video.current.play().catch(() => {});
      } else {
        pending.current = found.offset;
        setCurrent(found.segment);
      }
    },
    [day, current],
  );

  /** Emenda automática: ao acabar um arquivo entra o seguinte, e a fronteira de
   *  cinco minutos desaparece. */
  const advance = () => {
    const next = day?.segments.find((s) => s.at > current.at);
    if (!next) return;
    pending.current = 0;
    setCurrent(next);
  };

  const tick = () => {
    if (!current || !video.current) return;
    setPlayhead(new Date(+current.at + video.current.currentTime * 1000));
  };

  if (!day) {
    return (
      <p className="rounded-xl border border-white/10 bg-surface p-8 text-center text-sm text-neutral-400">
        Nenhuma gravação ainda.
      </p>
    );
  }

  return (
    // Em tela larga a lista fica ao lado, com a mesma altura do conjunto; em
    // tela estreita ela desce para baixo. É a diferença entre ler de relance e
    // rolar metros de página.
    <div className="mx-auto grid max-w-[1400px] gap-3 lg:grid-cols-[minmax(0,1fr)_300px] lg:items-start">
      <div className="min-w-0 space-y-3">
        <div className="relative aspect-video w-full overflow-hidden rounded-lg border border-white/10 bg-black">
          <video
            ref={video}
            controls
            playsInline
            preload="metadata"
            onTimeUpdate={tick}
            onEnded={advance}
            className="size-full object-contain"
          />
          {current && (
            <span className="pointer-events-none absolute left-2.5 top-2.5 rounded bg-black/60 px-2 py-1 text-[11px] font-medium tabular-nums">
              {current.at.toLocaleString("pt-BR")}
            </span>
          )}
        </div>

        <div className="rounded-xl border border-white/10 bg-surface p-3">
          <DayRail
            days={days}
            active={day}
            countFor={(d) => episodesOf(events, d.date).length}
            onPick={onPickDay}
          />
          <Timeline day={day} episodes={eps} current={current} playhead={playhead} onSeek={seek} />
          <div className="mt-2 flex items-center gap-3 text-[10px] text-neutral-400">
            <span><i className="mr-1 inline-block size-2.5 rounded-sm bg-motion align-[-1px]" />Movimento</span>
            <span><i className="mr-1 inline-block size-2.5 rounded-sm bg-rec/70 align-[-1px]" />Gravado</span>
            <span className="hidden sm:inline"><i className="mr-1 inline-block size-2.5 rounded-sm bg-live align-[-1px]" />Agora</span>
            <span className="ml-auto font-medium tabular-nums text-white">
              {playhead ? hhmmss(playhead) : ""}
            </span>
          </div>
        </div>
      </div>

      {/* Altura fixa em tela larga: sem ela o `flex-1` da lista não tem o que
          dividir, e a coluna cresce empurrando a página em vez de rolar. */}
      <div className="min-h-0 lg:sticky lg:top-16 lg:h-[calc(100dvh-5rem)]">
        <EpisodeList episodes={eps} onPick={seek} />
      </div>
    </div>
  );
}
