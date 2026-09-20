import { durationLabel, hhmmss } from "../lib/argos";

// Cada coisa com sua marca, para distinguir de relance sem ler o rótulo.
const MARCAS = {
  pessoa: { icone: "👤", cor: "bg-alert" },
  carro: { icone: "🚗", cor: "bg-rec" },
  caminhão: { icone: "🚚", cor: "bg-rec" },
  ônibus: { icone: "🚌", cor: "bg-rec" },
  moto: { icone: "🏍", cor: "bg-rec" },
  bicicleta: { icone: "🚲", cor: "bg-rec" },
  cachorro: { icone: "🐕", cor: "bg-live" },
  gato: { icone: "🐈", cor: "bg-live" },
};

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
                {/* A barra ganha a cor do que foi reconhecido: pessoa em
                    vermelho, veículo em azul, bicho em verde. Quando o
                    detector não reconheceu nada, continua âmbar de
                    "movimento" — que é a verdade, não uma suposição. */}
                <i className={`h-7 w-[3px] shrink-0 rounded-sm ${
                  MARCAS[ep.rotulos?.[0]]?.cor || "bg-motion"
                }`} />
                <span className="min-w-0">
                  <b className="flex items-center gap-1.5 text-xs font-medium tabular-nums">
                    {hhmmss(ep.start)}
                    {ep.rotulos?.length > 0 && (
                      <span className="rounded bg-trough px-1.5 py-0.5 text-[10px] font-normal">
                        {ep.rotulos.map((r) => `${MARCAS[r]?.icone || ""} ${r}`).join(" · ")}
                      </span>
                    )}
                  </b>
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
