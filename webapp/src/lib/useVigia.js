import { useCallback, useEffect, useRef, useState } from "react";
import { byDay, startedAt } from "./vigia";

/** Busca e mantém vivos o índice de gravações e os eventos da câmera. */
export function useVigia() {
  const [segments, setSegments] = useState([]);
  const [events, setEvents] = useState([]);
  const [error, setError] = useState(null);
  const [loaded, setLoaded] = useState(false);

  const load = useCallback(async () => {
    try {
      const [index, raw] = await Promise.all([
        fetch("/live/index.json", { cache: "no-store" }).then((r) => {
          if (!r.ok) throw new Error(`índice ${r.status}`);
          return r.json();
        }),
        fetch("/live/events.jsonl", { cache: "no-store" })
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
      setError(null);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoaded(true);
    }
  }, []);

  useEffect(() => {
    load();
    // O índice é reescrito a cada minuto; recarregar mantém a linha do tempo
    // viva sem obrigar ninguém a atualizar a página.
    const timer = setInterval(load, 60000);
    return () => clearInterval(timer);
  }, [load]);

  return { segments, events, days: byDay(segments), error, loaded, reload: load };
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
