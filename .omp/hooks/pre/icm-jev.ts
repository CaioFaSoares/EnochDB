// Hook do ICM do EnochDB. Ver docs/agents/jev.md §Hooks.
//
// Três coisas, todas derivadas e sem chamar o Jev (o Jev roda no `eval`, pelo `/icm`):
//   1. guarda    (tool_call)   protege o que o agente não deve reescrever e pede o dono para fechar etapa;
//   2. frescor   (tool_result, agent_end)  se o artefato de uma etapa mudou desde o último recibo do Jev,
//                devolve a instrução de rodar o gate e, no fim do turno, dispara um turno para isso;
//   3. status    (session_start, agent_end)  uma linha no rodapé com etapa e frescor.
//
// Falha segura: erro do próprio hook em `tool_call` bloqueia (política do omp); em `tool_result` e
// `agent_end` o hook nunca atrapalha o fluxo, só deixa de avisar.
import { relative, resolve } from "node:path";
import type { ExtensionAPI, ExtensionContext } from "@oh-my-pi/pi-coding-agent";
import { etapaAtual, sprints } from "../../../docs/_index/icm-conduzir.mjs";
import { RAIZ, carregarConfig, fatosDoSprint, frescor } from "../../../docs/_index/jev-gate.mjs";
import type { Frescor } from "../../../docs/_index/jev-gate.mjs";

const HANDOVER = /^docs\/_sprints\/([^/]+)\/(\d{2}_[a-z]+)\/handovers\/[^/]+\.md$/;
const ADR = /^docs\/adr\/\d{4}-[^/]+\.md$/;
const CABECALHO_EDIT = /^\[([^\]#]+)#[0-9A-Za-z]{2,}\]/gm;
/** Etapa com loop próprio (`/icm implement`): o recibo dela nasce em `fechar`, não pelo aviso do hook. */
const ETAPAS_SEM_AVISO: Record<string, true> = { "05_implement": true };

interface Vigente {
  sprint: string;
  etapa: string;
}

function texto(valor: unknown): string {
  return typeof valor === "string" ? valor : "";
}

/** Caminhos que um `edit` ou `write` toca, relativos à raiz do repositório; fora dela, descartados. */
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

/** Sprint mais recente e a etapa em que ela está, derivados das fichas. */
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
      ? "ainda não tem recibo do Jev"
      : `mudou desde o recibo ${f.recibo ?? "anterior"} (${(f.mudados ?? []).join(", ")})`;
  return [
    `[ICM · hook] O gate \`${f.gate}\` da etapa ${v.etapa} ${porque}.`,
    "Rode o gate antes de continuar ou de dizer que está pronto. No `eval` (js):",
    "```js",
    "const c = await import(`${process.cwd()}/docs/_index/icm-conduzir.mjs`);",
    `console.log(c.painel(await c.conduzir({ judge, judgeBatch }, { sprint: "${v.sprint}", issues: false })));`,
    "```",
    "Isso grava o recibo em `handovers/jev.jsonl`. Confirme cada ACHADO e INCERTO no artefato antes de resumir: o veredito é consultivo e fechar a etapa é do dono.",
  ].join("\n");
}

function guarda(rels: string[], conteudo: string): { motivo: string; rel: string } | null {
  const g = carregarConfig().conducao.guarda;
  const recibos = new RegExp(g.proteger_recibos);
  const ficha = new RegExp(g.ficha_de_etapa);
  const fechar = new RegExp(g.status_que_pede_dono);
  for (const rel of rels) {
    if (g.proteger.some(p => rel === p || (p.endsWith("/") && rel.startsWith(p)))) {
      return { rel, motivo: "é a casa das perguntas, dos limiares e do código do Jev; mudá-la muda o que o gate considera aprovado" };
    }
    if (recibos.test(rel)) return { rel, motivo: "o recibo só é escrito pelo código do gate (registrar), nunca à mão" };
    if (ficha.test(rel) && fechar.test(conteudo)) return { rel, motivo: "fechar etapa é do dono (A3): o gate do Jev é consultivo" };
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
      ctx.ui.setStatus("icm", `ICM ${v.sprint} · ${v.etapa} · ${f.gate ?? "sem gate"}: ${f.estado.replace("_", " ")}`);
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
      const ok = await ctx.ui.confirm("ICM: escrita protegida", `${razao}\n\nPermitir esta escrita?`);
      if (ok) return;
      return { block: true, reason: `${razao} O dono negou.` };
    }
    return { block: true, reason: `${razao} Sem o dono presente, a escrita foi bloqueada.` };
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
