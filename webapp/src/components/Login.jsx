import { useState } from "react";

export default function Login({ onDone }) {
  const [user, setUser] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState(null);
  const [busy, setBusy] = useState(false);

  const submit = async (event) => {
    event.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const res = await fetch("/api/login", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ user, password }),
      });
      if (!res.ok) {
        const data = await res.json().catch(() => ({}));
        throw new Error(data.error || "não foi possível entrar");
      }
      onDone(await res.json());
    } catch (err) {
      setError(err.message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="flex min-h-dvh items-center justify-center p-4">
      <form
        onSubmit={submit}
        className="w-full max-w-xs space-y-4 rounded-xl border border-white/10 bg-surface p-6"
      >
        <div className="space-y-1 text-center">
          <div className="mx-auto mb-3 size-12 rounded-full bg-gradient-to-b from-motion to-alert" />
          <h1 className="text-base font-semibold">Vigia</h1>
          <p className="text-xs text-neutral-400">Entre para ver as câmeras</p>
        </div>

        <label className="block space-y-1">
          <span className="text-xs text-neutral-400">Usuário</span>
          <input
            value={user}
            onChange={(e) => setUser(e.target.value)}
            autoComplete="username"
            autoFocus
            required
            className="w-full rounded-md border border-white/10 bg-canvas px-3 py-2 text-sm outline-none focus:border-rec"
          />
        </label>

        <label className="block space-y-1">
          <span className="text-xs text-neutral-400">Senha</span>
          <input
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            autoComplete="current-password"
            required
            className="w-full rounded-md border border-white/10 bg-canvas px-3 py-2 text-sm outline-none focus:border-rec"
          />
        </label>

        {error && <p className="text-xs text-alert">{error}</p>}

        <button
          type="submit"
          disabled={busy}
          className="w-full rounded-md bg-rec py-2 text-sm font-medium text-white transition hover:brightness-110 disabled:opacity-50"
        >
          {busy ? "Entrando…" : "Entrar"}
        </button>
      </form>
    </div>
  );
}
