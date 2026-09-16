import { useEffect, useState } from "react";

/** Quem tem acesso.
 *
 *  O papel "leitura" existe para dar acesso sem dar controle — a pessoa vê as
 *  câmeras e as gravações, mas não muda retenção nem cria usuários. */
export default function Users({ me }) {
  const [users, setUsers] = useState([]);
  const [form, setForm] = useState({ user: "", password: "", role: "leitura" });
  const [status, setStatus] = useState(null);
  const [busy, setBusy] = useState(false);

  const load = () =>
    fetch("/api/users", { cache: "no-store" }).then((r) => r.json()).then(setUsers).catch(() => {});

  useEffect(() => { load(); }, []);

  const send = async (url, body, ok) => {
    setBusy(true);
    setStatus(null);
    try {
      const res = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error || "falhou");
      setStatus({ kind: "ok", text: ok });
      setForm({ user: "", password: "", role: "leitura" });
      load();
    } catch (err) {
      setStatus({ kind: "error", text: err.message });
    } finally {
      setBusy(false);
    }
  };

  return (
    <section className="space-y-4 rounded-xl border border-white/10 bg-surface p-4">
      <h3 className="text-[13px] font-semibold">Usuários</h3>

      <ul className="divide-y divide-white/5 rounded-lg border border-white/10">
        {users.map((u) => (
          <li key={u.user} className="flex items-center gap-3 px-3 py-2">
            <span className="text-sm">{u.user}</span>
            <span className={`rounded px-1.5 py-0.5 text-[10px] ${
              u.role === "admin" ? "bg-rec/20 text-rec" : "bg-trough text-neutral-400"
            }`}>
              {u.role}
            </span>
            {u.user === me && <span className="text-[10px] text-neutral-500">você</span>}
            <span className="flex-1" />
            {u.user !== me && users.length > 1 && (
              <button
                onClick={() => send("/api/users/delete", { user: u.user }, `${u.user} removido.`)}
                disabled={busy}
                className="text-[11px] text-neutral-500 transition hover:text-alert"
              >
                Remover
              </button>
            )}
          </li>
        ))}
      </ul>

      <div className="space-y-2 border-t border-white/10 pt-3">
        <p className="text-[11px] text-neutral-400">
          Criar usuário ou trocar a senha de um existente
        </p>
        <div className="grid gap-2 sm:grid-cols-[1fr_1fr_auto_auto]">
          <input
            placeholder="usuário"
            value={form.user}
            onChange={(e) => setForm({ ...form, user: e.target.value })}
            className="rounded-md border border-white/10 bg-canvas px-2 py-1.5 text-sm outline-none focus:border-rec"
          />
          <input
            type="password"
            placeholder="senha (mín. 8)"
            value={form.password}
            onChange={(e) => setForm({ ...form, password: e.target.value })}
            className="rounded-md border border-white/10 bg-canvas px-2 py-1.5 text-sm outline-none focus:border-rec"
          />
          <select
            value={form.role}
            onChange={(e) => setForm({ ...form, role: e.target.value })}
            className="rounded-md border border-white/10 bg-canvas px-2 py-1.5 text-sm outline-none focus:border-rec"
          >
            <option value="leitura">leitura</option>
            <option value="admin">admin</option>
          </select>
          <button
            onClick={() => send("/api/users", form, `${form.user} salvo.`)}
            disabled={busy || !form.user || form.password.length < 8}
            className="rounded-md bg-rec px-3 py-1.5 text-xs font-medium transition hover:brightness-110 disabled:opacity-40"
          >
            Salvar
          </button>
        </div>
        {status && (
          <p className={`text-[11px] ${status.kind === "error" ? "text-alert" : "text-live"}`}>
            {status.text}
          </p>
        )}
      </div>
    </section>
  );
}
