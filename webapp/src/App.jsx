import { useEffect, useMemo, useState } from "react";
import LiveView from "./components/LiveView";
import RecordingsView from "./components/RecordingsView";
import { useVigia } from "./lib/useVigia";
import { bytes, defaultDay, sameDay } from "./lib/vigia";

export default function App() {
  const { segments, events, days, error, loaded } = useVigia();
  const [tab, setTab] = useState("live");
  const [dayAt, setDayAt] = useState(null);

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
    <div className="min-h-dvh">
      <header className="sticky top-0 z-10 flex items-center gap-3 border-b border-white/10 bg-canvas px-3 py-2 pt-[max(0.5rem,env(safe-area-inset-top))]">
        <nav className="flex rounded-lg bg-trough p-0.5">
          {[["live", "Ao vivo"], ["rec", "Gravações"]].map(([id, label]) => (
            <button
              key={id}
              onClick={() => setTab(id)}
              className={`rounded-md px-3 py-1 text-[13px] transition ${
                tab === id ? "bg-neutral-600 text-white" : "text-neutral-400 hover:text-neutral-200"
              }`}
            >
              {label}
            </button>
          ))}
        </nav>

        <div className="ml-auto flex items-center gap-1.5 text-[11px] text-neutral-400">
          <i className={`size-[7px] rounded-full ${up ? "bg-live" : "bg-alert"}`} />
          {/* Em tela estreita só o essencial: o ponto já diz se está no ar. */}
          <span className="hidden sm:inline">
            {up ? `${segments.length} trechos · ${bytes(total)}` : `fora do ar${error ? ` — ${error}` : ""}`}
          </span>
          <span className="sm:hidden">{up ? bytes(total) : "fora do ar"}</span>
        </div>
      </header>

      <main className="p-3">
        {tab === "live" ? (
          <LiveView active={tab === "live"} lastMotion={lastMotion} />
        ) : (
          <RecordingsView days={days} events={events} day={day} onPickDay={(d) => setDayAt(d.date)} />
        )}
      </main>
    </div>
  );
}
