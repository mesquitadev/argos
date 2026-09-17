import { useCallback, useEffect, useState } from "react";

/** As câmeras do sistema, e a adoção das que estão na rede.
 *
 *  Pedir um IP digitado é a pior primeira pergunta que um NVR pode fazer.
 *  Câmera ONVIF responde a um multicast dizendo fabricante e modelo — então a
 *  tela mostra o que existe na rede e você adota. */
export default function Cameras() {
  const [cameras, setCameras] = useState([]);
  const [achadas, setAchadas] = useState(null);
  const [buscando, setBuscando] = useState(false);
  const [editando, setEditando] = useState(null);
  const [status, setStatus] = useState(null);

  const carregar = useCallback(
    () => fetch("/api/cameras", { cache: "no-store" }).then((r) => r.json()).then(setCameras).catch(() => {}),
    [],
  );
  useEffect(() => { carregar(); }, [carregar]);

  const buscar = async () => {
    setBuscando(true);
    setStatus(null);
    try {
      const res = await fetch("/api/cameras/descobrir", { cache: "no-store" });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error || "a busca falhou");
      setAchadas(data);
    } catch (err) {
      setStatus({ kind: "error", text: err.message });
    } finally {
      setBuscando(false);
    }
  };

  const salvar = async (camera) => {
    setStatus(null);
    try {
      const res = await fetch("/api/cameras", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(camera),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error || "não foi possível salvar");
      setStatus({ kind: "ok", text: `${data.name} salva. A gravação começa em alguns segundos.` });
      setEditando(null);
      setAchadas(null);
      carregar();
    } catch (err) {
      setStatus({ kind: "error", text: err.message });
    }
  };

  const remover = async (id) => {
    const res = await fetch("/api/cameras/delete", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ id }),
    });
    if (res.ok) {
      setStatus({ kind: "ok", text: "Câmera removida. As gravações dela continuam no disco." });
      carregar();
    }
  };

  return (
    <div className="space-y-4">
      <section className="rounded-xl border border-white/10 bg-surface p-4">
        <header className="mb-3 flex items-center gap-2">
          <h3 className="text-[13px] font-semibold">Câmeras</h3>
          <span className="text-[10px] tabular-nums text-neutral-500">{cameras.length}</span>
          <span className="flex-1" />
          <button
            onClick={buscar}
            disabled={buscando}
            className="rounded-md bg-rec px-3 py-1.5 text-xs font-medium transition hover:brightness-110 disabled:opacity-50"
          >
            {buscando ? "Procurando na rede…" : "Procurar na rede"}
          </button>
        </header>

        {cameras.length === 0 ? (
          <p className="py-4 text-center text-xs text-neutral-500">
            Nenhuma câmera ainda. Procure na rede para adotar a primeira.
          </p>
        ) : (
          <ul className="divide-y divide-white/5 rounded-lg border border-white/10">
            {cameras.map((c) => (
              <li key={c.id} className="flex items-center gap-3 px-3 py-2.5">
                <i className={`size-2 shrink-0 rounded-full ${c.enabled ? "bg-live" : "bg-neutral-600"}`} />
                <div className="min-w-0">
                  <p className="truncate text-sm">{c.name}</p>
                  <p className="truncate text-[10px] tabular-nums text-neutral-500">
                    {c.id} · {c.host}:{c.rtsp_port}
                    {!c.tem_senha && " · sem senha"}
                  </p>
                </div>
                <span className="flex-1" />
                <button onClick={() => setEditando(c)} className="text-[11px] text-neutral-400 hover:text-neutral-200">
                  Editar
                </button>
                <button onClick={() => remover(c.id)} className="text-[11px] text-neutral-500 hover:text-alert">
                  Remover
                </button>
              </li>
            ))}
          </ul>
        )}

        {status && (
          <p className={`mt-2 text-[11px] ${status.kind === "error" ? "text-alert" : "text-live"}`}>
            {status.text}
          </p>
        )}
      </section>

      {achadas && (
        <section className="rounded-xl border border-white/10 bg-surface p-4">
          <h3 className="mb-3 text-[13px] font-semibold">
            Na rede <span className="text-[10px] font-normal text-neutral-500">{achadas.length} encontrada(s)</span>
          </h3>
          {achadas.length === 0 ? (
            <p className="text-xs text-neutral-500">
              Nenhuma câmera ONVIF respondeu. Algumas vêm com ONVIF desligado de fábrica —
              nesse caso, adicione pelo endereço.
            </p>
          ) : (
            <ul className="space-y-1.5">
              {achadas.map((a) => (
                <li key={a.host} className="flex items-center gap-3 rounded-lg border border-white/10 px-3 py-2.5">
                  <div className="min-w-0">
                    <p className="truncate text-sm">{a.name}{a.hardware && ` · ${a.hardware}`}</p>
                    <p className="text-[10px] tabular-nums text-neutral-500">{a.host}</p>
                  </div>
                  <span className="flex-1" />
                  {a.ja_registrada ? (
                    <span className="text-[11px] text-neutral-500">já adotada</span>
                  ) : (
                    <button
                      onClick={() => setEditando({
                        id: "", name: a.name, host: a.host, rtsp_port: 554,
                        user: "admin", password: "",
                        path: "/cam/realmonitor?channel=1&subtype=0", enabled: true,
                      })}
                      className="rounded-md bg-rec px-3 py-1.5 text-xs font-medium transition hover:brightness-110"
                    >
                      Adotar
                    </button>
                  )}
                </li>
              ))}
            </ul>
          )}
        </section>
      )}

      {editando && (
        <Formulario
          camera={editando}
          onSalvar={salvar}
          onCancelar={() => setEditando(null)}
        />
      )}
    </div>
  );
}

const CAMPOS = [
  { k: "id", label: "Identificador", dica: "vira o nome da pasta no disco; não muda depois" },
  { k: "name", label: "Nome", dica: "como aparece na tela" },
  { k: "host", label: "Endereço", dica: "IP da câmera" },
  { k: "rtsp_port", label: "Porta RTSP", dica: "554 na maioria" },
  { k: "user", label: "Usuário", dica: "" },
  { k: "password", label: "Senha", dica: "em branco mantém a atual", tipo: "password" },
  { k: "path", label: "Caminho do fluxo", dica: "padrão Dahua/Intelbras", largo: true },
];

function Formulario({ camera, onSalvar, onCancelar }) {
  const [form, setForm] = useState(camera);
  const novo = !camera.id;

  return (
    <section className="rounded-xl border border-rec/40 bg-surface p-4">
      <h3 className="mb-3 text-[13px] font-semibold">
        {novo ? "Adotar câmera" : `Editar ${camera.name}`}
      </h3>

      <div className="grid gap-3 sm:grid-cols-2">
        {CAMPOS.map((c) => (
          <label key={c.k} className={c.largo ? "sm:col-span-2" : ""}>
            <span className="text-[11px] text-neutral-400">{c.label}</span>
            <input
              type={c.tipo || "text"}
              value={form[c.k] ?? ""}
              placeholder={novo && c.k === "id" ? "ex.: garagem" : ""}
              disabled={!novo && c.k === "id"}
              onChange={(e) => setForm({ ...form, [c.k]: e.target.value })}
              className="mt-1 w-full rounded-md border border-white/10 bg-canvas px-2 py-1.5 text-sm outline-none focus:border-rec disabled:opacity-50"
            />
            {c.dica && <span className="mt-0.5 block text-[10px] text-neutral-600">{c.dica}</span>}
          </label>
        ))}
      </div>

      <div className="mt-4 flex items-center gap-2">
        <button
          onClick={() => onSalvar(form)}
          disabled={!form.id || !form.host}
          className="rounded-md bg-rec px-3 py-1.5 text-xs font-medium transition hover:brightness-110 disabled:opacity-40"
        >
          {novo ? "Adotar" : "Salvar"}
        </button>
        <button onClick={onCancelar} className="rounded-md px-2 py-1.5 text-xs text-neutral-400">
          Cancelar
        </button>
      </div>
    </section>
  );
}
