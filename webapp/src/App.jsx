import { useCallback, useEffect, useMemo, useState } from "react";
import LiveView from "./components/LiveView";
import Login from "./components/Login";
import Nav from "./components/Nav";
import RecordingsView from "./components/RecordingsView";
import Settings from "./components/Settings";
import StoragePanel from "./components/StoragePanel";
import Wall from "./components/Wall";
import { useCameras, useVigia } from "./lib/useVigia";
import { bytes, defaultDay, sameDay } from "./lib/vigia";

export default function App() {
  // `undefined` é "ainda não sei", diferente de `null`, que é "não autenticado".
  // Sem essa distinção a tela de login pisca antes de a sessão ser conferida.
  const [session, setSession] = useState(undefined);

  useEffect(() => {
    fetch("/api/session", { cache: "no-store" })
      .then((r) => (r.ok ? r.json() : null))
      .then((s) => setSession(s?.user ? s : null))
      .catch(() => setSession(null));
  }, []);

  if (session === undefined) return <div className="min-h-dvh" />;
  if (session === null) return <Login onDone={setSession} />;
  return <Shell session={session} onLogout={() => setSession(null)} />;
}

function Shell({ session, onLogout }) {
  const cameras = useCameras();
  // A câmera em foco. Sem escolha explícita, a primeira — e o mosaico só
  // aparece quando há mais de uma, porque grade de um quadro é só um quadro
  // com borda.
  const [focada, setFocada] = useState(null);
  const camera = cameras.find((c) => c.id === focada) || cameras[0] || null;

  const { segments, events, detections, days, error, loaded } = useVigia(camera?.id);
  const [tab, setTab] = useState("live");
  const [dayAt, setDayAt] = useState(null);

  const logout = useCallback(async () => {
    await fetch("/api/logout", { method: "POST" }).catch(() => {});
    onLogout();
  }, [onLogout]);

  // O dia escolhido é guardado como data, não como objeto: a cada recarga do
  // índice os objetos são novos, e uma referência antiga perderia a seleção.
  const day = useMemo(() => {
    if (!days.length) return null;
    return days.find((d) => dayAt && sameDay(d.date, dayAt)) || defaultDay(days);
  }, [days, dayAt]);

  useEffect(() => {
    if (day && !dayAt) setDayAt(day.date);
  }, [day, dayAt]);

  const lastMotion = useMemo(() => {
    const starts = events.filter((e) => e.action === "Start").map((e) => e.at);
    return starts.length ? new Date(Math.max(...starts)) : null;
  }, [events]);

  const total = useMemo(() => segments.reduce((sum, s) => sum + (s.bytes || 0), 0), [segments]);
  const up = loaded && !error;

  return (
    // Cabine, não página: a altura é a da tela e nada rola por fora. Cada
    // painel cuida da própria rolagem, que é como um sistema de vigilância se
    // usa — olhando, não navegando.
    <div className="flex h-dvh overflow-hidden">
      <Nav
        active={tab}
        onPick={setTab}
        user={session.user}
        onLogout={logout}
        status={{
          up,
          text: up ? `${segments.length} trechos · ${bytes(total)}` : "gravador fora do ar",
        }}
      />

      <div className="flex min-w-0 flex-1 flex-col">
        {/* Cabeçalho só no celular: na tela larga essa informação vive no rail,
            e repetir seria gastar altura que o vídeo quer. */}
        <header className="flex shrink-0 items-center gap-2 border-b border-white/10 px-3 py-2 pt-[max(0.5rem,env(safe-area-inset-top))] md:hidden">
          <span className="size-6 rounded-full bg-gradient-to-b from-motion to-alert" />
          <span className="text-sm font-semibold">Vigia</span>
          <span className="ml-auto flex items-center gap-1.5 text-[11px] text-neutral-400">
            <i className={`size-[7px] rounded-full ${up ? "bg-live" : "bg-alert"}`} />
            {up ? bytes(total) : "fora do ar"}
          </span>
          <button onClick={logout} className="text-[11px] text-neutral-500">Sair</button>
        </header>

        <main
          className={`min-h-0 flex-1 p-3 pb-[calc(0.75rem+3.5rem)] md:pb-3 ${
            tab === "live" || tab === "rec"
              ? "overflow-hidden max-md:overflow-y-auto"
              : "overflow-y-auto"
          }`}
        >
          {tab === "live" &&
            (cameras.length > 1 && !focada ? (
              <Wall cameras={cameras} onFocar={(c) => setFocada(c.id)} />
            ) : (
              <LiveView
                active
                camera={camera}
                lastMotion={lastMotion}
                podeVoltar={cameras.length > 1}
                onVoltar={() => setFocada(null)}
              />
            ))}
          {tab === "rec" && (
            <RecordingsView
              days={days}
              events={events}
              detections={detections}
              day={day}
              cameras={cameras}
              camera={camera}
              onPickCamera={(id) => { setFocada(id); setDayAt(null); }}
              onPickDay={(d) => setDayAt(d.date)}
            />
          )}
          {tab === "disk" && <StoragePanel />}
          {tab === "settings" && <Settings me={session.user} />}
        </main>
      </div>
    </div>
  );
}
