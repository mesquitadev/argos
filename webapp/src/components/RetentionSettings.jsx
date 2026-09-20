import { useEffect, useState } from "react";
import { bytes } from "../lib/argos";

const FIELDS = [
  { key: "MAX_DAYS", label: "Guardar por", unit: "dias", hint: "Gravação mais velha que isto é apagada." },
  { key: "MAX_GB", label: "Teto de espaço", unit: "GB", hint: "Acima disso, apaga do mais antigo." },
  { key: "MIN_FREE_GB", label: "Folga mínima", unit: "GB", hint: "Espaço livre que nunca é consumido." },
  { key: "CHECK_MINUTES", label: "Verificar a cada", unit: "min", hint: "De quanto em quanto tempo confere." },
];

export default function RetentionSettings() {
  const [policy, setPolicy] = useState(null);
  const [plan, setPlan] = useState(null);
  const [draft, setDraft] = useState({});
  const [status, setStatus] = useState(null);
  const [confirming, setConfirming] = useState(false);
  const [busy, setBusy] = useState(false);

  const load = () =>
    fetch("/api/retention", { cache: "no-store" })
      .then((r) => r.json())
      .then((d) => {
        setPolicy(d.policy);
        setPlan(d.plan);
        setDraft(d.policy);
      })
      .catch((e) => setStatus({ kind: "error", text: e.message }));

  useEffect(() => { load(); }, []);

  const save = async () => {
    setBusy(true);
    setStatus(null);
    try {
      const res = await fetch("/api/retention", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(draft),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error || "não foi possível salvar");
      setPolicy(data.policy);
      setPlan(data.plan);
      setStatus({ kind: "ok", text: "Política salva." });
    } catch (err) {
      setStatus({ kind: "error", text: err.message });
    } finally {
      setBusy(false);
    }
  };

  const purge = async () => {
    setBusy(true);
    setConfirming(false);
    try {
      const res = await fetch("/api/retention/purge", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ confirm: true }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error || "falhou");
      setStatus({
        kind: "ok",
        text: data.removed
          ? `${data.removed} trechos apagados, ${bytes(data.bytes)} liberados.`
          : "Nada a apagar: tudo está dentro da política.",
      });
      load();
    } catch (err) {
      setStatus({ kind: "error", text: err.message });
    } finally {
      setBusy(false);
    }
  };

  if (!policy) return <p className="text-xs text-neutral-500">Carregando política…</p>;

  const changed = FIELDS.some((f) => Number(draft[f.key]) !== Number(policy[f.key]));

  return (
    <section className="rounded-xl border border-white/10 bg-surface p-4">
      <header className="mb-3 flex items-center gap-2">
        <h3 className="text-[13px] font-semibold">Retenção</h3>
        <label className="ml-auto flex items-center gap-1.5 text-[11px] text-neutral-400">
          <input
            type="checkbox"
            checked={draft.ENABLED === 1}
            onChange={(e) => setDraft({ ...draft, ENABLED: e.target.checked ? 1 : 0 })}
            className="accent-rec"
          />
          ativa
        </label>
      </header>

      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        {FIELDS.map((f) => (
          <label key={f.key} className="block">
            <span className="text-[11px] text-neutral-400">{f.label}</span>
            <span className="mt-1 flex items-center gap-1.5">
              <input
                type="number"
                value={draft[f.key] ?? ""}
                onChange={(e) => setDraft({ ...draft, [f.key]: e.target.value })}
                className="w-full rounded-md border border-white/10 bg-canvas px-2 py-1.5 text-sm tabular-nums outline-none focus:border-rec"
              />
              <span className="text-[11px] text-neutral-500">{f.unit}</span>
            </span>
            <span className="mt-0.5 block text-[10px] leading-snug text-neutral-600">{f.hint}</span>
          </label>
        ))}
      </div>

      {/* Prever antes de apagar: a diferença entre "7 dias" e "7 dias apaga
          40 GB e leva até anteontem" é o que faz alguém parar antes de
          confirmar. */}
      {plan && (
        <p className="mt-3 rounded-md bg-canvas px-3 py-2 text-[11px] text-neutral-400">
          {plan.count === 0 ? (
            "Com esta política, nada seria apagado agora."
          ) : (
            <>
              Apagaria <b className="text-motion">{plan.count} trechos</b> ({bytes(plan.bytes)}), por{" "}
              {plan.reason}, até{" "}
              <b className="text-motion">{new Date(plan.newest).toLocaleString("pt-BR")}</b>.
            </>
          )}
        </p>
      )}

      {status && (
        <p className={`mt-2 text-[11px] ${status.kind === "error" ? "text-alert" : "text-live"}`}>
          {status.text}
        </p>
      )}

      <div className="mt-3 flex flex-wrap items-center gap-2">
        <button
          onClick={save}
          disabled={!changed || busy}
          className="rounded-md bg-rec px-3 py-1.5 text-xs font-medium transition hover:brightness-110 disabled:opacity-40"
        >
          Salvar
        </button>
        {changed && (
          <button
            onClick={() => setDraft(policy)}
            className="rounded-md px-2 py-1.5 text-xs text-neutral-400 hover:text-neutral-200"
          >
            Desfazer
          </button>
        )}

        <span className="flex-1" />

        {confirming ? (
          <>
            <span className="text-[11px] text-alert">Apagar de vez?</span>
            <button
              onClick={purge}
              disabled={busy}
              className="rounded-md bg-alert px-3 py-1.5 text-xs font-medium transition hover:brightness-110"
            >
              Sim, expurgar
            </button>
            <button
              onClick={() => setConfirming(false)}
              className="rounded-md px-2 py-1.5 text-xs text-neutral-400"
            >
              Cancelar
            </button>
          </>
        ) : (
          <button
            onClick={() => setConfirming(true)}
            disabled={busy}
            className="rounded-md border border-white/10 px-3 py-1.5 text-xs text-neutral-300 transition hover:border-alert hover:text-alert"
          >
            Expurgar agora
          </button>
        )}
      </div>
    </section>
  );
}
