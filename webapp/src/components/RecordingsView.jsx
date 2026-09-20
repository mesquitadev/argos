import { useCallback, useEffect, useRef, useState } from "react";
import DayRail from "./DayRail";
import Export from "./Export";
import EpisodeList from "./EpisodeList";
import Timeline from "./Timeline";
import { defaultSegment, episodes as episodesOf, hhmmss, locate, rotularEpisodios } from "../lib/argos";

export default function RecordingsView({ days, events, detections, day, cameras, camera, onPickCamera, onPickDay }) {
  const video = useRef(null);
  const [current, setCurrent] = useState(null);
  const [playhead, setPlayhead] = useState(null);
  const pending = useRef(0);
  // Marcação em dois cliques: o primeiro fixa o início, o segundo o fim. Um
  // arraste seria mais elegante, mas quebra no toque, e o celular é onde mais
  // se pede um trecho.
  const [selecao, setSelecao] = useState(null);
  const [exportando, setExportando] = useState(false);

  const eps = day ? rotularEpisodios(episodesOf(events, day.date), detections || []) : [];

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

  /** Marca início e fim do que vai ser exportado. */
  const marcar = (instante) => {
    setSelecao((atual) => {
      if (!atual?.inicio || atual.fim) return { inicio: instante, fim: null };
      // Marcar para trás é legítimo: quem viu o fim primeiro marca de trás
      // para a frente, e trocar a ordem aqui evita um erro sem sentido.
      const [inicio, fim] = [atual.inicio, instante].sort((a, b) => a - b);
      return { inicio, fim };
    });
  };

  const tick = () => {
    if (!current || !video.current) return;
    setPlayhead(new Date(+current.at + video.current.currentTime * 1000));
  };

  if (!day) {
    return (
      <p className="rounded-xl border border-white/10 bg-surface p-8 text-center text-sm text-neutral-400">
        {camera ? `Nenhuma gravação de ${camera.name} ainda.` : "Nenhuma câmera adotada."}
      </p>
    );
  }

  return (
    // A altura disponível é dividida: o vídeo fica com a sobra, a linha do
    // tempo tem tamanho próprio e a lista rola por dentro. Em tela estreita
    // tudo empilha e a página rola, porque um celular em pé não mostra as três
    // coisas sem espremer nenhuma.
    <div className="mx-auto grid h-full max-w-[1400px] grid-rows-[minmax(0,1fr)_auto] gap-3 md:h-full lg:grid-cols-[minmax(0,1fr)_300px] lg:grid-rows-1 lg:items-stretch">
      <div className="flex min-h-0 min-w-0 flex-col gap-3 lg:row-span-1">
        {/* Um palco que recebe a altura, e dentro dele o quadro dimensionado
            pela proporção. Dar `flex-1` ao próprio quadro fazia a altura vir do
            layout e a proporção virar tarja preta dentro da moldura. */}
        <div className="grid min-h-0 flex-1 place-items-center [container-type:size]">
        <div className="relative w-full max-w-full aspect-video overflow-hidden rounded-lg border border-white/10 bg-black md:w-[min(100cqw,calc(100cqh*16/9))] aspect-video">
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
            <span className="glass pointer-events-none absolute left-2.5 top-2.5 rounded-full px-2.5 py-1 text-[11px] font-medium tabular-nums text-white">
              {current.at.toLocaleString("pt-BR")}
            </span>
          )}
        </div>
        </div>

        <div className="shrink-0 rounded-xl border border-white/10 bg-surface p-3">
          {/* Seletor de câmera antes do dia: escolher o dia de outra câmera
              seria escolher duas vezes. */}
          {cameras?.length > 1 && (
            <div className="mb-2 flex gap-1 overflow-x-auto pb-1">
              {cameras.map((c) => (
                <button
                  key={c.id}
                  onClick={() => onPickCamera(c.id)}
                  className={`shrink-0 rounded-md px-2.5 py-1 text-[11px] transition ${
                    c.id === camera?.id
                      ? "bg-rec/20 text-white ring-1 ring-rec/70"
                      : "bg-trough/60 text-neutral-400 hover:bg-trough"
                  }`}
                >
                  {c.name}
                </button>
              ))}
            </div>
          )}
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
            <span className="ml-auto flex items-center gap-2">
              {selecao?.inicio && selecao?.fim ? (
                <>
                  <span className="text-live">
                    {hhmmss(selecao.inicio)} → {hhmmss(selecao.fim)}
                  </span>
                  <button
                    onClick={() => setExportando(true)}
                    className="rounded bg-live px-2 py-0.5 text-[10px] font-medium text-black"
                  >
                    Exportar
                  </button>
                  <button onClick={() => setSelecao(null)} className="text-neutral-500">
                    limpar
                  </button>
                </>
              ) : (
                <span className="text-neutral-600">
                  {selecao?.inicio ? "shift+clique no fim do trecho" : "shift+clique marca um trecho"}
                </span>
              )}
              <span className="font-medium tabular-nums text-white">
                {playhead ? hhmmss(playhead) : ""}
              </span>
            </span>
          </div>
        </div>
      </div>

      {/* Altura fixa em tela larga: sem ela o `flex-1` da lista não tem o que
          dividir, e a coluna cresce empurrando a página em vez de rolar. */}
      <div className="min-h-0 lg:h-full">
        <EpisodeList episodes={eps} onPick={seek} />
      </div>

      {exportando && selecao?.inicio && selecao?.fim && (
        <Export
          inicio={selecao.inicio}
          fim={selecao.fim}
          onFechar={() => setExportando(false)}
        />
      )}
    </div>
  );
}
