import { dayLabel } from "../lib/argos";

/** Os dias com gravação, em abas horizontais.
 *
 *  Cada um mostra quantos episódios teve, para a escolha acontecer antes de
 *  abrir a linha do tempo: um dia sem movimento não precisa ser visitado. */
export default function DayRail({ days, active, countFor, onPick }) {
  return (
    <div className="-mx-1 flex gap-1.5 overflow-x-auto px-1 pb-2 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
      {days.map((day) => {
        const count = countFor(day);
        const on = day === active;
        return (
          <button
            key={+day.date}
            onClick={() => onPick(day)}
            className={`min-w-[92px] shrink-0 rounded-md px-2.5 py-1.5 text-left text-xs transition ${
              on
                ? "bg-rec/20 text-white ring-1 ring-rec/70"
                : "bg-trough/60 text-neutral-400 hover:bg-trough"
            }`}
          >
            <span className="block font-medium">{dayLabel(day.date)}</span>
            <span className="block text-[10px] tabular-nums text-neutral-500">
              {count ? (
                <>
                  <i className="mr-1 inline-block size-[5px] rounded-full bg-motion align-middle not-italic" />
                  {count}
                </>
              ) : (
                "sem movimento"
              )}
            </span>
          </button>
        );
      })}
    </div>
  );
}
