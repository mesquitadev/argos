import { useEffect, useState } from "react";
import RetentionSettings from "./RetentionSettings";
import Users from "./Users";

const TABS = [
  { id: "retencao", label: "Retenção" },
  { id: "usuarios", label: "Usuários" },
  { id: "sistema", label: "Sistema" },
];

export default function Settings({ me }) {
  const [tab, setTab] = useState("retencao");

  return (
    <div className="mx-auto max-w-3xl space-y-4">
      <nav className="flex gap-1 rounded-lg bg-trough p-0.5">
        {TABS.map((t) => (
          <button
            key={t.id}
            onClick={() => setTab(t.id)}
            className={`flex-1 rounded-md px-3 py-1.5 text-[13px] transition ${
              tab === t.id ? "bg-neutral-600 text-white" : "text-neutral-400 hover:text-neutral-200"
            }`}
          >
            {t.label}
          </button>
        ))}
      </nav>

      {tab === "retencao" && <RetentionSettings />}
      {tab === "usuarios" && <Users me={me} />}
      {tab === "sistema" && <System />}
    </div>
  );
}

function System() {
  const [info, setInfo] = useState(null);

  useEffect(() => {
    fetch("/api/system", { cache: "no-store" }).then((r) => r.json()).then(setInfo).catch(() => {});
  }, []);

  if (!info) return <p className="text-xs text-neutral-500">Carregando…</p>;

  const rows = [
    ["Câmera", info.camera.id],
    ["Endereço da câmera", info.camera.host || "—"],
    ["Duração do trecho", `${info.segment_seconds}s`],
    ["Pasta das gravações", info.recordings_path],
    ["Fuso do servidor", info.timezone],
    ["Hora do servidor", new Date(info.server_time).toLocaleString("pt-BR")],
  ];

  return (
    <section className="rounded-xl border border-white/10 bg-surface p-4">
      <h3 className="mb-3 text-[13px] font-semibold">Sistema</h3>
      <dl className="divide-y divide-white/5 text-sm">
        {rows.map(([k, v]) => (
          <div key={k} className="flex items-baseline gap-3 py-2">
            <dt className="text-[11px] text-neutral-400">{k}</dt>
            <dd className="ml-auto truncate text-right tabular-nums">{v}</dd>
          </div>
        ))}
      </dl>
      {/* A hora do servidor está aqui de propósito: foi um relógio em UTC que
          desalinhou a linha do tempo por horas, e o sintoma não apontava para
          a causa. */}
      <p className="mt-2 text-[10px] text-neutral-600">
        Se a hora do servidor divergir da sua, os horários das gravações saem errados.
      </p>
    </section>
  );
}
