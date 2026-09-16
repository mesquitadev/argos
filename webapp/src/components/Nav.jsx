import { useState } from "react";

/** A navegação do sistema.
 *
 *  Barra lateral em tela larga e barra inferior no celular — que é onde o
 *  polegar alcança. Abas no topo serviam para duas telas; com cinco seções, e
 *  com configurações que têm subseções, viram um amontoado. */
const SECTIONS = [
  { id: "live", label: "Ao vivo", icon: "M15 10l4.55-2.27A1 1 0 0121 8.6v6.8a1 1 0 01-1.45.87L15 14M5 18h8a2 2 0 002-2V8a2 2 0 00-2-2H5a2 2 0 00-2 2v8a2 2 0 002 2z" },
  { id: "rec", label: "Gravações", icon: "M4 6h16M4 12h16M4 18h16" },
  { id: "disk", label: "Armazenamento", icon: "M4 7v10c0 1.1 3.6 2 8 2s8-.9 8-2V7M4 7c0 1.1 3.6 2 8 2s8-.9 8-2M4 7c0-1.1 3.6-2 8-2s8 .9 8 2" },
  { id: "settings", label: "Configurações", icon: "M10.3 3.3a1 1 0 011.4 0l.9.9a1 1 0 00.9.3l1.2-.2a1 1 0 011.1.7l.4 1.2a1 1 0 00.6.6l1.2.4a1 1 0 01.7 1.1l-.2 1.2a1 1 0 00.3.9l.9.9a1 1 0 010 1.4l-.9.9a1 1 0 00-.3.9l.2 1.2a1 1 0 01-.7 1.1l-1.2.4a1 1 0 00-.6.6l-.4 1.2a1 1 0 01-1.1.7l-1.2-.2a1 1 0 00-.9.3l-.9.9a1 1 0 01-1.4 0l-.9-.9a1 1 0 00-.9-.3l-1.2.2a1 1 0 01-1.1-.7l-.4-1.2a1 1 0 00-.6-.6l-1.2-.4a1 1 0 01-.7-1.1l.2-1.2a1 1 0 00-.3-.9l-.9-.9a1 1 0 010-1.4l.9-.9a1 1 0 00.3-.9l-.2-1.2a1 1 0 01.7-1.1l1.2-.4a1 1 0 00.6-.6l.4-1.2a1 1 0 011.1-.7l1.2.2a1 1 0 00.9-.3zM12 15a3 3 0 100-6 3 3 0 000 6z" },
];

function Icon({ d }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6"
         strokeLinecap="round" strokeLinejoin="round" className="size-[18px] shrink-0">
      <path d={d} />
    </svg>
  );
}

export default function Nav({ active, onPick, status, user, onLogout }) {
  // A escolha fica guardada: num painel que se olha todo dia, ter de recolher o
  // menu a cada visita é atrito repetido.
  const [open, setOpen] = useState(() => {
    try {
      return localStorage.getItem("vigia.menu") !== "fechado";
    } catch {
      return true;
    }
  });

  const toggle = () => {
    setOpen((was) => {
      try {
        localStorage.setItem("vigia.menu", was ? "fechado" : "aberto");
      } catch {
        /* navegação privada bloqueia o armazenamento; o menu ainda funciona */
      }
      return !was;
    });
  };

  return (
    <>
      {/* Tela larga: rail à esquerda, com o estado do gravador no rodapé. */}
      <aside
        className={`hidden shrink-0 flex-col border-r border-white/10 bg-surface transition-[width] duration-200 md:flex ${
          open ? "w-52" : "w-[60px]"
        }`}
      >
        <div className="flex items-center gap-2 px-4 py-4">
          <span className="size-7 shrink-0 rounded-full bg-gradient-to-b from-motion to-alert" />
          {open && <span className="truncate text-sm font-semibold">Vigia</span>}
        </div>

        <nav className="flex-1 space-y-0.5 px-2">
          {SECTIONS.map((s) => (
            <button
              key={s.id}
              onClick={() => onPick(s.id)}
              // O rótulo vira dica quando recolhido: sem isso, só o ícone
              // obriga a adivinhar ou a abrir o menu para conferir.
              title={open ? undefined : s.label}
              className={`flex w-full items-center gap-2.5 rounded-md py-2 text-left text-[13px] transition ${
                open ? "px-3" : "justify-center px-0"
              } ${
                active === s.id
                  ? "bg-rec/20 text-white"
                  : "text-neutral-400 hover:bg-trough hover:text-neutral-200"
              }`}
            >
              <Icon d={s.icon} />
              {open && <span className="truncate">{s.label}</span>}
            </button>
          ))}
        </nav>

        <div className="space-y-2 border-t border-white/10 px-3 py-3 text-[11px]">
          <p
            className={`flex items-center gap-1.5 text-neutral-400 ${open ? "" : "justify-center"}`}
            title={open ? undefined : status.text}
          >
            <i className={`size-[7px] shrink-0 rounded-full ${status.up ? "bg-live" : "bg-alert"}`} />
            {open && <span className="truncate">{status.text}</span>}
          </p>
          {open && (
            <p className="flex items-center justify-between text-neutral-500">
              <span className="truncate">{user}</span>
              <button onClick={onLogout} className="shrink-0 hover:text-neutral-200">Sair</button>
            </p>
          )}
          <button
            onClick={toggle}
            title={open ? "Recolher menu" : "Expandir menu"}
            className={`flex w-full items-center gap-2 rounded-md py-1.5 text-neutral-500 transition hover:bg-trough hover:text-neutral-200 ${
              open ? "px-2" : "justify-center"
            }`}
          >
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8"
                 strokeLinecap="round" strokeLinejoin="round"
                 className={`size-4 transition-transform ${open ? "" : "rotate-180"}`}>
              <path d="M15 18l-6-6 6-6" />
            </svg>
            {open && "Recolher"}
          </button>
        </div>
      </aside>

      {/* Celular: barra inferior, onde o polegar alcança. */}
      <nav className="fixed inset-x-0 bottom-0 z-20 flex border-t border-white/10 bg-surface pb-[env(safe-area-inset-bottom)] md:hidden">
        {SECTIONS.map((s) => (
          <button
            key={s.id}
            onClick={() => onPick(s.id)}
            className={`flex flex-1 flex-col items-center gap-1 py-2 text-[10px] transition ${
              active === s.id ? "text-white" : "text-neutral-500"
            }`}
          >
            <Icon d={s.icon} />
            {s.label === "Armazenamento" ? "Disco" : s.label}
          </button>
        ))}
      </nav>
    </>
  );
}
