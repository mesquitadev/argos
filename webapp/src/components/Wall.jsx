import { useHls } from "../lib/useArgos";

/** O mosaico: todas as câmeras ao mesmo tempo.
 *
 *  É a tela que define um NVR. A grade se ajusta à quantidade — uma câmera
 *  ocupa tudo, quatro viram 2×2 — porque forçar grade fixa desperdiça tela com
 *  poucas câmeras e espreme com muitas. */
export default function Wall({ cameras, onFocar }) {
  if (cameras.length === 0) {
    return (
      <p className="rounded-xl border border-white/10 bg-surface p-8 text-center text-sm text-neutral-400">
        Nenhuma câmera adotada. Vá em Configurações › Câmeras e procure na rede.
      </p>
    );
  }

  // Colunas pela raiz quadrada: 1→1, 2..4→2, 5..9→3, e assim por diante.
  const colunas = Math.ceil(Math.sqrt(cameras.length));

  return (
    <div
      className="grid h-full min-h-0 gap-2"
      style={{
        gridTemplateColumns: `repeat(${colunas}, minmax(0, 1fr))`,
        gridAutoRows: "1fr",
      }}
    >
      {cameras.map((camera) => (
        <Painel key={camera.id} camera={camera} onFocar={onFocar} />
      ))}
    </div>
  );
}

function Painel({ camera, onFocar }) {
  const { ref, unsupported } = useHls(`/live/${camera.id}/${camera.id}.m3u8`, true);

  return (
    <button
      onClick={() => onFocar(camera)}
      className="group relative min-h-0 overflow-hidden rounded-lg border border-white/10 bg-black text-left transition hover:border-rec/60"
    >
      <video ref={ref} playsInline muted autoPlay className="size-full object-contain" />

      {unsupported && (
        <p className="absolute inset-0 flex items-center justify-center bg-surface text-xs text-neutral-400">
          sem suporte a HLS
        </p>
      )}

      <span className="glass pointer-events-none absolute left-2 top-2 flex items-center gap-1.5 rounded-full px-2 py-0.5 text-[10px] font-medium text-white">
        <i className="size-[6px] animate-pulse rounded-full bg-alert" />
        {camera.name}
      </span>
    </button>
  );
}
