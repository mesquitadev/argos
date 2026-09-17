import { useEffect, useRef, useState } from "react";
import { bytes, hhmmss } from "../lib/vigia";

/** Recortar um trecho e baixar.
 *
 *  É o pedido mais comum de um NVR — "me manda o vídeo daquela hora" — e o que
 *  hoje obriga a achar o arquivo no disco por SSH. O corte atravessa a
 *  fronteira entre arquivos, porque quem pede um intervalo não sabe nem
 *  precisa saber que a gravação vem em pedaços de cinco minutos. */
export default function Export({ inicio, fim, onFechar }) {
  const [trabalho, setTrabalho] = useState(null);
  const [erro, setErro] = useState(null);
  const sondagem = useRef(null);

  const duracao = (fim - inicio) / 1000;

  useEffect(() => () => clearInterval(sondagem.current), []);

  const exportar = async () => {
    setErro(null);
    try {
      const res = await fetch("/api/export", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          // Sem fuso na string: o servidor grava em hora local, e mandar UTC
          // faria o corte cair noutro momento do dia.
          start: semFuso(inicio),
          end: semFuso(fim),
        }),
      });
      const dados = await res.json();
      if (!res.ok) throw new Error(dados.error || "não foi possível exportar");
      setTrabalho(dados);
      acompanhar(dados.id);
    } catch (err) {
      setErro(err.message);
    }
  };

  /** Pergunta pelo andamento até ficar pronto.
   *
   *  A junção roda no servidor e pode levar segundos num intervalo longo;
   *  segurar a requisição aberta até o fim daria tempo esgotado no caminho. */
  const acompanhar = (id) => {
    clearInterval(sondagem.current);
    sondagem.current = setInterval(async () => {
      const res = await fetch(`/api/export/${id}`, { cache: "no-store" });
      const dados = await res.json();
      setTrabalho(dados);
      if (dados.state !== "working") clearInterval(sondagem.current);
    }, 1500);
  };

  return (
    <div className="fixed inset-0 z-30 flex items-center justify-center bg-black/60 p-4">
      <div className="w-full max-w-sm space-y-4 rounded-xl border border-white/10 bg-surface p-5">
        <h3 className="text-sm font-semibold">Exportar trecho</h3>

        <dl className="space-y-1.5 rounded-lg bg-canvas p-3 text-[12px]">
          <Linha termo="Início" valor={hhmmss(inicio)} />
          <Linha termo="Fim" valor={hhmmss(fim)} />
          <Linha termo="Duração" valor={`${Math.round(duracao)}s`} />
        </dl>

        {erro && <p className="text-[11px] text-alert">{erro}</p>}

        {trabalho?.state === "working" && (
          <p className="flex items-center gap-2 text-[11px] text-neutral-400">
            <i className="size-3 animate-spin rounded-full border-2 border-neutral-600 border-t-rec" />
            Juntando os trechos…
          </p>
        )}

        {trabalho?.state === "error" && (
          <p className="text-[11px] text-alert">{trabalho.error}</p>
        )}

        {trabalho?.state === "ready" && (
          <a
            href={trabalho.url}
            download
            className="block rounded-md bg-live py-2 text-center text-sm font-medium text-black transition hover:brightness-110"
          >
            Baixar · {bytes(trabalho.size)}
          </a>
        )}

        <div className="flex items-center gap-2">
          {!trabalho && (
            <button
              onClick={exportar}
              className="rounded-md bg-rec px-3 py-1.5 text-xs font-medium transition hover:brightness-110"
            >
              Exportar
            </button>
          )}
          <button onClick={onFechar} className="rounded-md px-2 py-1.5 text-xs text-neutral-400">
            {trabalho?.state === "ready" ? "Fechar" : "Cancelar"}
          </button>
        </div>

        <p className="text-[10px] leading-snug text-neutral-600">
          O vídeo é copiado sem recodificar: sai em segundos e com a mesma
          qualidade que a câmera gravou. O arquivo é apagado do servidor depois
          de seis horas.
        </p>
      </div>
    </div>
  );
}

/** ISO local, sem `Z` nem deslocamento — o servidor grava em hora local. */
function semFuso(data) {
  const pad = (n) => String(n).padStart(2, "0");
  return `${data.getFullYear()}-${pad(data.getMonth() + 1)}-${pad(data.getDate())}` +
         `T${pad(data.getHours())}:${pad(data.getMinutes())}:${pad(data.getSeconds())}`;
}

function Linha({ termo, valor }) {
  return (
    <div className="flex justify-between">
      <dt className="text-neutral-400">{termo}</dt>
      <dd className="tabular-nums">{valor}</dd>
    </div>
  );
}
