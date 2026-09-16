import { durationLabel } from "../lib/vigia";
import { useHls } from "../lib/useVigia";

/** O fluxo ao vivo, sem controles de reprodução — não há começo nem fim. */
export default function LiveView({ active, lastMotion }) {
  const { ref, unsupported } = useHls("/live/cam1.m3u8", active);
  const minutes = lastMotion ? Math.round((Date.now() - lastMotion) / 60000) : null;

  return (
    <div className="relative mx-auto aspect-video w-full max-w-[1400px] overflow-hidden rounded-lg border border-white/10 bg-black">
      <video ref={ref} playsInline muted autoPlay className="size-full object-contain" />

      {unsupported && (
        <p className="absolute inset-0 flex items-center justify-center bg-surface px-4 text-center text-sm text-neutral-400">
          Este navegador não reproduz HLS.
        </p>
      )}

      {/* Gradiente em vez de barra opaca: escurece o topo o suficiente para o
          texto se ler sobre qualquer cena, sem cortar um retângulo na imagem. */}
      <div className="pointer-events-none absolute inset-x-0 top-0 flex items-center gap-3 bg-gradient-to-b from-black/65 to-transparent px-3 py-2">
        <span className="flex items-center gap-1.5 text-[10px] font-semibold tracking-wide">
          {/* A pulsação carrega informação: um ponto parado não distingue
              imagem ao vivo de imagem congelada. */}
          <i className="size-[7px] animate-pulse rounded-full bg-alert" />
          AO VIVO
        </span>
        {minutes !== null && (
          <span className="ml-auto text-[10px] text-motion">
            {minutes < 1 ? "Movimento agora" : `Movimento há ${durationLabel(minutes * 60)}`}
          </span>
        )}
      </div>
    </div>
  );
}
