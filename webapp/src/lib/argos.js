// Regras de domínio, separadas da interface: são as mesmas que o app nativo
// aplica, e foi conferindo-as contra a câmera real que elas ficaram assim.

/** Quanto dura cada arquivo gravado. */
export const SEGMENT_SECONDS = 300;
export const DAY_SECONDS = 86400;

/** Duas atividades separadas por menos de dois minutos são a mesma coisa
 *  acontecendo. A câmera dispara início e fim a cada oscilação: sem agrupar,
 *  uma pessoa atravessando a cena vira seis linhas idênticas de "Movimento". */
const EPISODE_GAP = 120;

const pad = (n) => String(n).padStart(2, "0");

/** `cam1_2026-09-16_21-04-47.mp4` → Date local. */
export function startedAt(segment) {
  const m = /(\d{4})-(\d{2})-(\d{2})_(\d{2})-(\d{2})-(\d{2})/.exec(
    segment.started || segment.path || "",
  );
  if (!m) return null;
  return new Date(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +m[6]);
}

export const startOfDay = (d) => new Date(d.getFullYear(), d.getMonth(), d.getDate());
export const sameDay = (a, b) => a && b && startOfDay(a).getTime() === startOfDay(b).getTime();
export const hhmmss = (d) => `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
export const hhmm = (d) => `${pad(d.getHours())}:${pad(d.getMinutes())}`;

export function bytes(n) {
  if (!n) return "—";
  const units = ["B", "KB", "MB", "GB", "TB"];
  let i = 0;
  while (n >= 1024 && i < units.length - 1) { n /= 1024; i += 1; }
  return `${n.toFixed(i ? 1 : 0)} ${units[i]}`;
}

export function durationLabel(seconds) {
  const s = Math.round(seconds);
  if (s < 60) return `${s}s`;
  const m = Math.floor(s / 60);
  return m < 60 ? `${m} min` : `${Math.floor(m / 60)}h ${m % 60}min`;
}

export function dayLabel(date) {
  const today = startOfDay(new Date()).getTime();
  const d = startOfDay(date).getTime();
  if (d === today) return "Hoje";
  if (d === today - 86400000) return "Ontem";
  return date.toLocaleDateString("pt-BR", { weekday: "short", day: "numeric", month: "short" });
}

/** Pares início/fim viram períodos. Um início sem fim — uma queda de conexão
 *  engole o `Stop` — vira período curto, em vez de sumir da linha do tempo ou
 *  esticar até o infinito. */
function periods(events, day) {
  const open = new Map();
  const out = [];
  const ofDay = events.filter((e) => sameDay(e.at, day)).sort((a, b) => a.at - b.at);

  for (const e of ofDay) {
    if (e.action === "Start") open.set(e.code, e.at);
    else if (open.has(e.code)) {
      out.push({ start: open.get(e.code), end: e.at });
      open.delete(e.code);
    }
  }
  for (const [, start] of open) out.push({ start, end: new Date(+start + 5000) });
  return out.sort((a, b) => a.start - b.start);
}

/** Junta ao episódio o que o detector reconheceu naquele intervalo.
 *
 *  Um episódio pode ter várias detecções — um carro passando e uma pessoa
 *  atrás. Guardamos o conjunto de rótulos, porque é o que o olho lê de
 *  relance: "carro, pessoa" diz mais que duas linhas separadas. */
export function rotularEpisodios(eps, detections) {
  return eps.map((ep) => {
    const dentro = detections.filter(
      (d) => d.at >= new Date(+ep.start - 5000) && d.at <= new Date(+ep.end + 5000),
    );
    const rotulos = [...new Set(dentro.flatMap((d) => d.objetos.map((o) => o.o_que)))];
    const confianca = Math.max(0, ...dentro.flatMap((d) => d.objetos.map((o) => o.confianca)));
    return { ...ep, rotulos, confianca };
  });
}

export function episodes(events, day) {
  const ps = periods(events, day);
  if (!ps.length) return [];

  const out = [];
  let { start, end } = ps[0];
  let count = 1;

  for (const p of ps.slice(1)) {
    if ((p.start - end) / 1000 <= EPISODE_GAP) {
      end = new Date(Math.max(+end, +p.end));
      count += 1;
    } else {
      out.push({ start, end, count });
      ({ start, end } = p);
      count = 1;
    }
  }
  out.push({ start, end, count });
  return out;
}

/** Agrupa por dia, do mais recente para o mais antigo — a ordem em que alguém
 *  procura uma gravação. */
export function byDay(segments) {
  const map = new Map();
  for (const s of segments) {
    const key = startOfDay(s.at).getTime();
    if (!map.has(key)) map.set(key, []);
    map.get(key).push(s);
  }
  return [...map.entries()]
    .map(([key, segs]) => ({ date: new Date(key), segments: segs.sort((a, b) => a.at - b.at) }))
    .sort((a, b) => b.date - a.date);
}

/** O dia a abrir: prefere hoje.
 *
 *  "O mais recente da lista" seria o óbvio, mas o relógio do gravador pode
 *  estar adiantado e criar um dia no futuro — e abrir num dia vazio faz o app
 *  parecer sem gravação nenhuma. */
export function defaultDay(days) {
  const now = new Date();
  return (
    days.find((d) => sameDay(d.date, now)) ||
    days.find((d) => d.date <= now) ||
    days[0] ||
    null
  );
}

/** O trecho a abrir num dia.
 *
 *  O mais novo é o que o gravador está escrevendo neste instante: abrir esse dá
 *  tela preta, porque o arquivo ainda não tem índice. O anterior é o mais
 *  recente que realmente se assiste. */
export function defaultSegment(day) {
  if (!day?.segments.length) return null;
  const ordered = [...day.segments].sort((a, b) => b.at - a.at);
  return ordered.length > 1 ? ordered[1] : ordered[0];
}

/** Qual trecho contém um instante, e a que altura dele pular.
 *
 *  Quem clica na linha do tempo pensa em horário, não em arquivo. Se o instante
 *  cai num buraco sem gravação, o começo do trecho seguinte é a resposta
 *  honesta. */
export function locate(day, target) {
  const segs = day?.segments ?? [];
  const inside = segs.filter(
    (s) => s.at <= target && target < new Date(+s.at + SEGMENT_SECONDS * 1000),
  ).pop();
  const chosen = inside || segs.find((s) => s.at > target) || segs[segs.length - 1];
  if (!chosen) return null;
  return { segment: chosen, offset: Math.max(0, (target - chosen.at) / 1000) };
}

/** Posição de um instante na faixa do dia, em porcentagem. */
export function positionOf(date, day) {
  const base = startOfDay(day.date);
  const frac = (date - base) / 1000 / DAY_SECONDS;
  return Math.max(0, Math.min(1, frac)) * 100;
}
