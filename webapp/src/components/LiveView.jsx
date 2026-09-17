import { durationLabel } from "../lib/vigia";
import { useHls } from "../lib/useVigia";

/** O fluxo ao vivo, sem controles de reprodução — não há começo nem fim. */
export default function LiveView({ active, camera, lastMotion, podeVoltar, onVoltar }) {
  const { ref, unsupported } = useHls(
    camera ? `/live/${camera.id}/${camera.id}.m3u8` : null,
    active && !!camera,
  );
  const minutes = lastMotion ? Math.round((Date.now() - lastMotion) / 60000) : null;

  return (
    // `h-full` com proporção fixa e `max-w-full`: quando a altura é o limite,
    // o quadro encolhe pela altura e a largura acompanha — sem tarja preta, que
    // é o que aparece quando só a largura manda.
    <div className="grid size-full min-h-0 place-items-center [container-type:size]">
      <div className="relative w-full max-w-full aspect-video overflow-hidden rounded-lg border border-white/10 bg-black md:w-[min(100cqw,calc(100cqh*16/9))] aspect-video">
      <video ref={ref} playsInline muted autoPlay className="size-full object-contain" />

      {unsupported && (
        <p className="absolute inset-0 flex items-center justify-center bg-surface px-4 text-center text-sm text-neutral-400">
          Este navegador não reproduz HLS.
        </p>
      )}

      {/* Selos flutuando sobre a cena, em vez de uma faixa atravessando a
          imagem: ocupam só o que precisam e deixam o resto do quadro livre. */}
      <span className="glass pointer-events-none absolute left-2.5 top-2.5 flex items-center gap-1.5 rounded-full px-2.5 py-1 text-[10px] font-semibold tracking-wide text-white">
        {/* A pulsação carrega informação: um ponto parado não distingue imagem
            ao vivo de imagem congelada. */}
        <i className="size-[7px] animate-pulse rounded-full bg-alert shadow-[0_0_6px_var(--color-alert)]" />
        AO VIVO
        {camera && <span className="font-medium normal-case tracking-normal">{camera.name}</span>}
      </span>

      {podeVoltar && (
        <button
          onClick={onVoltar}
          className="glass absolute right-2.5 top-2.5 rounded-full px-2.5 py-1 text-[10px] font-medium text-white transition hover:brightness-125"
        >
          Ver todas
        </button>
      )}

      {/* Embaixo à direita de propósito: a câmera grava o próprio horário no
          canto de cima, e os dois se sobrepunham. */}
      {minutes !== null && (
        <span className="glass pointer-events-none absolute bottom-2.5 right-2.5 flex items-center gap-1.5 rounded-full px-2.5 py-1 text-[10px] font-medium text-white">
          <i className="size-[6px] rounded-full bg-motion shadow-[0_0_6px_var(--color-motion)]" />
          {minutes < 1 ? "Movimento agora" : `Movimento há ${durationLabel(minutes * 60)}`}
        </span>
      )}
      </div>
    </div>
  );
}
