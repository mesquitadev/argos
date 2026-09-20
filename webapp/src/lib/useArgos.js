import { useCallback, useEffect, useRef, useState } from "react";
import { byDay, startedAt } from "./argos";

/** As câmeras registradas. */
export function useCameras() {
  const [cameras, setCameras] = useState([]);
  useEffect(() => {
    const load = () =>
      fetch("/api/cameras", { cache: "no-store" })
        .then((r) => (r.ok ? r.json() : []))
        .then((lista) => setCameras(lista.filter((c) => c.enabled)))
        .catch(() => {});
    load();
    // Adotar uma câmera noutra aba deve refletir aqui sem recarregar a página.
    const timer = setInterval(load, 30000);
    return () => clearInterval(timer);
  }, []);
  return cameras;
}

/** Busca e mantém vivos o índice de gravações e os eventos de uma câmera. */
export function useArgos(cameraId) {
  const [segments, setSegments] = useState([]);
  const [events, setEvents] = useState([]);
  const [detections, setDetections] = useState([]);
  const [error, setError] = useState(null);
  const [loaded, setLoaded] = useState(false);

  const load = useCallback(async () => {
    try {
      // A API lê o disco a cada chamada: o disco é a verdade, e um índice
      // mantido à parte mostraria gravação que a retenção já apagou.
      const sufixo = cameraId ? `?camera=${encodeURIComponent(cameraId)}` : "";
      const [index, raw, brutoDet] = await Promise.all([
        fetch(`/api/recordings${sufixo}`, { cache: "no-store" }).then((r) => {
          if (!r.ok) throw new Error(`índice ${r.status}`);
          return r.json();
        }),
        fetch(`/api/events${sufixo}`, { cache: "no-store" })
          .then((r) => (r.ok ? r.text() : ""))
          .catch(() => ""),
        fetch(`/api/detections${sufixo}`, { cache: "no-store" })
          .then((r) => (r.ok ? r.text() : ""))
          .catch(() => ""),
      ]);

      setSegments(
        (index.segments || [])
          .map((s) => ({ ...s, at: startedAt(s) }))
          .filter((s) => s.at)
          .sort((a, b) => a.at - b.at),
      );

      // Uma linha por evento: uma linha escrita pela metade no momento da
      // leitura não pode derrubar o resto.
      setEvents(
        raw
          .split("\n")
          .map((line) => {
            try {
              const e = JSON.parse(line);
              return { ...e, at: new Date(e.at) };
            } catch {
              return null;
            }
          })
          .filter((e) => e && !Number.isNaN(+e.at)),
      );
      // O que o detector reconheceu, indexado pelo instante do evento: é o que
      // transforma "movimento" em "pessoa" ou "carro" na linha do tempo.
      const porInstante = new Map();
      for (const linha of brutoDet.split("\n")) {
        try {
          const d = JSON.parse(linha);
          if (d?.at) porInstante.set(new Date(d.at).getTime(), d.objetos || []);
        } catch {
          // linha escrita pela metade no momento da leitura
        }
      }
      setDetections([...porInstante.entries()].map(([at, objetos]) => ({ at: new Date(at), objetos })));

      setError(null);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoaded(true);
    }
  }, [cameraId]);

  useEffect(() => {
    load();
    // O índice é reescrito a cada minuto; recarregar mantém a linha do tempo
    // viva sem obrigar ninguém a atualizar a página.
    const timer = setInterval(load, 60000);
    return () => clearInterval(timer);
  }, [load]);

  return { segments, events, detections, days: byDay(segments), error, loaded, reload: load };
}

/** Liga um fluxo HLS a um elemento de vídeo.
 *
 *  Safari e iOS tocam HLS direto. Os demais precisam da biblioteca, que vai
 *  no pacote e não numa CDN — a casa não deve depender de internet para ver a
 *  própria câmera. */
export function useHls(url, enabled) {
  const ref = useRef(null);
  const [unsupported, setUnsupported] = useState(false);

  useEffect(() => {
    const video = ref.current;
    if (!video || !enabled) return undefined;

    let hls;
    let retry;

    const start = async () => {
      if (video.canPlayType("application/vnd.apple.mpegurl")) {
        video.src = url;
      } else {
        const { default: Hls } = await import("hls.js");
        if (!Hls.isSupported()) {
          setUnsupported(true);
          return;
        }
        hls = new Hls({
          // Buffer curto: num fluxo ao vivo, buffer grande é atraso garantido.
          maxBufferLength: 6,
          liveSyncDurationCount: 2,
          // Volta para a borda sozinho quando fica para trás: cada engasgo de
          // rede acumula atraso, e em minutos o "ao vivo" mostra o passado.
          liveMaxLatencyDurationCount: 6,
        });
        hls.loadSource(url);
        hls.attachMedia(video);
        hls.on(Hls.Events.ERROR, (_, data) => {
          if (!data.fatal) return;
          hls.destroy();
          hls = null;
          retry = setTimeout(start, 3000);
        });
      }
      video.play().catch(() => {});
    };

    start();
    return () => {
      clearTimeout(retry);
      hls?.destroy();
      video.removeAttribute("src");
      video.load();
    };
  }, [url, enabled]);

  return { ref, unsupported };
}
