import { useEffect, useState } from "react";
import { bytes } from "../lib/vigia";

/** Quanto disco há, quanto se grava por dia, e quando começa a apagar.
 *
 *  A pergunta que importa num DVR não é "quantos GB", é "quantos dias eu
 *  tenho" — e nenhuma das duas é visível olhando o disco. */
export default function StoragePanel() {
  const [data, setData] = useState(null);
  const [error, setError] = useState(null);

  useEffect(() => {
    const load = () =>
      fetch("/api/storage", { cache: "no-store" })
        .then((r) => (r.ok ? r.json() : Promise.reject(new Error(`erro ${r.status}`))))
        .then(setData)
        .catch((e) => setError(e.message));
    load();
    const timer = setInterval(load, 300000);
    return () => clearInterval(timer);
  }, []);

  if (error) return <p className="text-xs text-alert">{error}</p>;
  if (!data) return <p className="text-xs text-neutral-500">Medindo…</p>;

  const usedPct = (data.disk.used / data.disk.total) * 100;
  const peak = Math.max(...data.by_day.map((d) => d.bytes), 1);
  const recent = data.by_day.slice(-14);

  return (
    <div className="mx-auto max-w-[1400px] space-y-3">
      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <Card label="Histórico" value={`${Math.floor(data.span_days)} dias`}
              hint={data.oldest ? `desde ${new Date(data.oldest).toLocaleDateString("pt-BR")}` : ""} />
        <Card label="Gravado" value={bytes(data.bytes)} hint={`${data.segments} trechos`} />
        <Card label="Por dia" value={bytes(data.bytes_per_day)} hint="média de 7 dias" />
        <Card
          label="Enche em"
          value={data.days_until_full ? `${Math.floor(data.days_until_full)} dias` : "—"}
          hint={`${bytes(data.disk.free)} livres`}
          // Menos de uma semana de folga é quando a retenção começa a apagar
          // gravação que talvez importe.
          alert={data.days_until_full != null && data.days_until_full < 7}
        />
      </div>

      <section className="rounded-xl border border-white/10 bg-surface p-4">
        <h3 className="mb-2 text-[13px] font-semibold">Disco</h3>
        <div className="h-2.5 overflow-hidden rounded-full bg-trough">
          <div
            className={`h-full ${usedPct > 90 ? "bg-alert" : "bg-rec"}`}
            style={{ width: `${usedPct}%` }}
          />
        </div>
        <p className="mt-1.5 text-[11px] tabular-nums text-neutral-400">
          {bytes(data.disk.used)} de {bytes(data.disk.total)} usados · {bytes(data.disk.free)} livres
        </p>
      </section>

      <section className="rounded-xl border border-white/10 bg-surface p-4">
        <h3 className="mb-3 text-[13px] font-semibold">Gravação por dia</h3>
        <div className="flex h-28 items-end gap-1">
          {recent.map((d) => (
            // `h-full` no invólucro: sem altura definida, a porcentagem da
            // barra não tem a que se referir e ela não desenha.
            <div key={d.day} className="group flex h-full flex-1 items-end" title={`${d.day} · ${bytes(d.bytes)}`}>
              <div
                className="w-full rounded-t bg-rec/70 transition group-hover:bg-rec"
                style={{ height: `${Math.max(3, (d.bytes / peak) * 100)}%` }}
              />
            </div>
          ))}
        </div>
        <div className="mt-1.5 flex justify-between text-[10px] tabular-nums text-neutral-500">
          <span>{recent[0]?.day.slice(5)}</span>
          <span>{recent.at(-1)?.day.slice(5)}</span>
        </div>
      </section>
    </div>
  );
}

function Card({ label, value, hint, alert }) {
  return (
    <div className="rounded-xl border border-white/10 bg-surface p-3.5">
      <p className="text-[11px] text-neutral-400">{label}</p>
      <p className={`mt-0.5 text-lg font-semibold tabular-nums ${alert ? "text-alert" : ""}`}>{value}</p>
      <p className="text-[10px] text-neutral-500">{hint}</p>
    </div>
  );
}
