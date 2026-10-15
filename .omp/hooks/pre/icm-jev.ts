// EnochDB's ICM hook. See docs/agents/jev.md §Hooks.
//
// Three things, all derived and without calling Jev (Jev runs in `eval`, through `/icm`):
//   1. guard      (tool_call)   protects what the agent must not rewrite and asks the owner to close a stage;
//   2. freshness  (tool_result, agent_end)  if a stage's artifact changed since Jev's last receipt,
//                it returns the instruction to run the gate and, at the end of the turn, triggers a turn for that;
//   3. status     (session_start, agent_end)  a line in the footer with stage and freshness.
//
// Fail safe: an error in the hook itself in `tool_call` blocks (omp policy); in `tool_result` and
// `agent_end` the hook never hinders the flow, it just stops warning.
import { relative, resolve } from "node:path";
import type { ExtensionAPI, ExtensionContext } from "@oh-my-pi/pi-coding-agent";
import { etapaAtual, sprints } from "../../../docs/_index/icm-conduzir.mjs";
import { RAIZ, carregarConfig, fatosDoSprint, frescor } from "../../../docs/_index/jev-gate.mjs";
import type { Frescor } from "../../../docs/_index/jev-gate.mjs";

const HANDOVER = /^docs\/_sprints\/([^/]+)\/(\d{2}_[a-z]+)\/handovers\/[^/]+\.md$/;
const ADR = /^docs\/adr\/\d{4}-[^/]+\.md$/;
const CABECALHO_EDIT = /^\[([^\]#]+)#[0-9A-Za-z]{2,}\]/gm;
/** Stage with its own loop (`/icm implement`): its receipt is born in `fechar`, not from the hook warning. */
const ETAPAS_SEM_AVISO: Record<string, true> = { "05_implement": true };

interface Vigente {
  sprint: string;
  etapa: string;
}

function texto(valor: unknown): string {
  return typeof valor === "string" ? valor : "";
}

/** Paths an `edit` or `write` touches, relative to the repository root; outside it, discarded. */
function alvos(input: Record<string, unknown>, cwd: string): string[] {
  const brutos = new Set<string>();
  if (typeof input.path === "string") brutos.add(input.path.replace(/:\d+(-\d+)?$/, ""));
  if (Array.isArray(input.paths)) for (const p of input.paths) if (typeof p === "string") brutos.add(p);
  for (const m of texto(input.input).matchAll(CABECALHO_EDIT)) brutos.add(m[1]);
  const rels: string[] = [];
  for (const p of brutos) {
    const rel = relative(RAIZ, resolve(cwd, p));
    if (rel && !rel.startsWith("..")) rels.push(rel);
  }
  return rels;
}

/** Most recent sprint and the stage it is in, derived from the cards. */
function vigente(): Vigente | null {
  const sprint = sprints().at(-1);
  if (!sprint) return null;
  const etapa = etapaAtual(fatosDoSprint(sprint));
  return etapa ? { sprint, etapa: etapa.nome } : null;
}

const ESTADOS_VELHOS: Partial<Record<Frescor["estado"], true>> = { sem_recibo: true, desatualizado: true };

function diretiva(v: Vigente, f: Frescor): string {
  const porque =
    f.estado === "sem_recibo"
      ? "does not have a Jev receipt yet"
      : `changed since receipt ${f.recibo ?? "anterior"} (${(f.mudados ?? []).join(", ")})`;
  return [
    `[ICM · hook] The \`${f.gate}\` gate of stage ${v.etapa} ${porque}.`,
    "Run the gate before continuing or saying you are ready. In `eval` (js):",
    "```js",
    "const c = await import(`${process.cwd()}/docs/_index/icm-conduzir.mjs`);",
    `console.log(c.painel(await c.conduzir({ judge, judgeBatch }, { sprint: "${v.sprint}", issues: false })));`,
    "```",
    "This writes the receipt to `handovers/jev.jsonl`. Confirm each ACHADO and INCERTO in the artifact before summarizing: the verdict is advisory and closing the stage belongs to the owner.",
  ].join("\n");
}

function guarda(rels: string[], conteudo: string): { motivo: string; rel: string } | null {
  const g = carregarConfig().conducao.guarda;
  const recibos = new RegExp(g.proteger_recibos);
  const ficha = new RegExp(g.ficha_de_etapa);
  const fechar = new RegExp(g.status_que_pede_dono);
  for (const rel of rels) {
    if (g.proteger.some(p => rel === p || (p.endsWith("/") && rel.startsWith(p)))) {
      return { rel, motivo: "it is the home of the questions, the thresholds and Jev's code; changing it changes what the gate considers approved" };
    }
    if (recibos.test(rel)) return { rel, motivo: "the receipt is only written by the gate code (registrar), never by hand" };
    if (ficha.test(rel) && fechar.test(conteudo)) return { rel, motivo: "closing a stage belongs to the owner (A3): Jev's gate is advisory" };
  }
  return null;
}

export default function icmJev(pi: ExtensionAPI): void {
  const avisadoNoTurno = new Set<string>();
  let ultimoDisparo = "";

  function status(ctx: ExtensionContext): void {
    if (!ctx.hasUI) return;
    try {
      const v = vigente();
      if (!v) return ctx.ui.setStatus("icm", undefined);
      const f = frescor(v.sprint, v.etapa);
      ctx.ui.setStatus("icm", `ICM ${v.sprint} · ${v.etapa} · ${f.gate ?? "no gate"}: ${f.estado.replace("_", " ")}`);
    } catch {
      ctx.ui.setStatus("icm", undefined);
    }
  }

  pi.on("session_start", async (_event, ctx) => status(ctx));
  pi.on("agent_start", async () => avisadoNoTurno.clear());

  pi.on("tool_call", async (event, ctx) => {
    if (event.toolName !== "edit" && event.toolName !== "write") return;
    const input: Record<string, unknown> = event.input;
    const achado = guarda(alvos(input, ctx.cwd), JSON.stringify(input));
    if (!achado) return;
    const razao = `ICM: ${achado.rel} — ${achado.motivo}.`;
    if (ctx.agent.kind === "main" && ctx.hasUI) {
      const ok = await ctx.ui.confirm("ICM: protected write", `${razao}\n\nAllow this write?`);
      if (ok) return;
      return { block: true, reason: `${razao} The owner denied it.` };
    }
    return { block: true, reason: `${razao} With no owner present, the write was blocked.` };
  });

  pi.on("tool_result", async (event, ctx) => {
    if (event.isError || ctx.agent.kind !== "main") return;
    if (event.toolName !== "edit" && event.toolName !== "write") return;
    try {
      const v = vigente();
      if (!v || ETAPAS_SEM_AVISO[v.etapa]) return;
      const toca = alvos(event.input, ctx.cwd).some(rel => {
        const h = HANDOVER.exec(rel);
        return h ? h[1] === v.sprint && h[2] === v.etapa : v.etapa === "02_domain" && ADR.test(rel);
      });
      if (!toca) return;
      const f = frescor(v.sprint, v.etapa);
      status(ctx);
      if (!ESTADOS_VELHOS[f.estado]) return;
      const chave = `${v.sprint}/${v.etapa}`;
      if (avisadoNoTurno.has(chave)) return;
      avisadoNoTurno.add(chave);
      return { additionalContext: diretiva(v, f) };
    } catch {
      return;
    }
  });

  pi.on("agent_end", async (event, ctx) => {
    if (ctx.agent.kind !== "main" || event.willContinue) return;
    try {
      const v = vigente();
      status(ctx);
      if (!v || ETAPAS_SEM_AVISO[v.etapa]) return;
      const f = frescor(v.sprint, v.etapa);
      if (!ESTADOS_VELHOS[f.estado]) return;
      const chave = `${v.sprint}/${v.etapa}/${f.recibo ?? "-"}/${(f.mudados ?? []).join(",")}`;
      if (chave === ultimoDisparo) return;
      ultimoDisparo = chave;
      pi.sendMessage({ customType: "icm-gate", content: diretiva(v, f), display: true }, { triggerTurn: true });
    } catch {
      return;
    }
  });
}
