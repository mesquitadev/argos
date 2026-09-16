import { durationLabel, hhmmss } from "../lib/vigia";

/** O que a câmera detectou, agrupado em episódios.
 *
 *  A lista crua repetia "Movimento" dezenas de vezes, porque a câmera publica
 *  um evento por oscilação. Agrupadas, cada linha passa a ser uma ocorrência
 *  real, com duração — que é a informação que faz escolher onde olhar. */
export default function EpisodeList({ episodes, onPick }) {
  const ordered = [...episodes].sort((a, b) => b.start - a.start);

  return (
    <section className="flex h-full min-h-0 flex-col rounded-xl border border-white/10 bg-surface max-lg:max-h-[40vh]">
      <header className="flex items-baseline gap-2 border-b border-white/10 px-3.5 py-2.5">
        <h2 className="text-[13px] font-semibold">Detecções</h2>
        <span className="text-[10px] tabular-nums text-neutral-500">
          {ordered.length
            ? `${ordered.length} ${ordered.length === 1 ? "ocorrência" : "ocorrências"}`
            : "nenhuma"}
        </span>
      </header>

      {ordered.length === 0 ? (
        <p className="p-4 text-center text-xs text-neutral-500">Nada detectado neste dia.</p>
      ) : (
        // Rola dentro de si em vez de esticar a página: 60 detecções num dia
        // movimentado deixavam a página com metros de altura.
        <ul className="min-h-0 flex-1 overflow-y-auto overscroll-contain p-1.5">
          {ordered.map((ep) => (
            <li key={+ep.start}>
              <button
                onClick={() => onPick(ep.start)}
                className="flex w-full items-center gap-2.5 rounded-md px-2 py-1.5 text-left transition hover:bg-trough"
              >
                {/* Barra de acento em vez de ícone repetido: dezenas de ícones
                    iguais não informam nada. */}
                <i className="h-7 w-[3px] shrink-0 rounded-sm bg-motion" />
                <span className="min-w-0">
                  <b className="block text-xs font-medium tabular-nums">{hhmmss(ep.start)}</b>
                  <span className="block text-[10px] text-neutral-500">
                    {durationLabel((ep.end - ep.start) / 1000)}
                    {ep.count > 1 && ` · ${ep.count} disparos`}
                  </span>
                </span>
              </button>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
