// graphify hook in EnochDB's ICM. See docs/agents/graphify.md.
//
// Three things, all derived and without an LLM:
//   1. guard    (tool_call)    delivers to the agent, before `read`/`grep`/`glob`/`bash`, what the graph already
//                              knows, using graphify's official hook-guard (loaded from the installed package,
//                              without a copy: updating graphify updates the guard);
//   2. freshness (session_start, agent_end)  rebuilds the graph in the background when it is missing, is
//                              behind HEAD or the turn wrote a file;
//   3. status   footer with the graph state.
//
// The graph is advisory (A4): a failure here never blocks or hinders the turn, it just stops warning.
import { execFile, execFileSync } from "node:child_process";
import type { ExtensionAPI, ExtensionContext } from "@oh-my-pi/pi-coding-agent";
import { RAIZ } from "../../../docs/_index/jev-gate.mjs";
import { ativo, estado, resumo } from "../../../docs/_index/graphify.mjs";

/** Path of the guard package in the installed graphify; `null` without graphify. */
function pacoteDaGuarda(): string | null {
  try {
    return execFileSync("graphify", ["pi", "guard", "path"], { encoding: "utf8", timeout: 5000 }).trim().split("\n").pop() || null;
  } catch {
    return null;
  }
}

type FabricaDeExtensao = (pi: ExtensionAPI) => void;

async function carregarGuarda(): Promise<FabricaDeExtensao | null> {
  const pacote = pacoteDaGuarda();
  if (!pacote) return null;
  try {
    const modulo = (await import(`${pacote}/index.ts`)) as { default?: FabricaDeExtensao };
    return typeof modulo.default === "function" ? modulo.default : null;
  } catch {
    return null;
  }
}

const guarda = await carregarGuarda();

export default function graphifyIcm(pi: ExtensionAPI): void {
  guarda?.(pi);

  let reconstruindo = false;
  let escritaNoTurno = false;

  function status(ctx: ExtensionContext): void {
    if (!ctx.hasUI) return;
    try {
      ctx.ui.setStatus("graphify", ativo() ? resumo(estado()) : undefined);
    } catch {
      ctx.ui.setStatus("graphify", undefined);
    }
  }

  /** Rebuilds without blocking the turn. graphify has its own lock, so two calls don't step on each other. */
  function reconstruir(ctx: ExtensionContext): void {
    if (reconstruindo || !ativo()) return;
    reconstruindo = true;
    execFile("graphify", ["update", "."], { cwd: RAIZ, timeout: 120_000 }, () => {
      reconstruindo = false;
      status(ctx);
    });
  }

  pi.on("session_start", async (_event, ctx) => {
    try {
      const e = estado();
      if (e.ativo && (!e.existe || !e.atual)) reconstruir(ctx);
    } catch {
      // without a graph, the ICM proceeds as before
    }
    status(ctx);
  });

  pi.on("agent_start", async () => {
    escritaNoTurno = false;
  });

  pi.on("tool_result", async event => {
    if (!event.isError && (event.toolName === "edit" || event.toolName === "write")) escritaNoTurno = true;
  });

  pi.on("agent_end", async (event, ctx) => {
    if (ctx.agent.kind !== "main" || event.willContinue) return;
    if (escritaNoTurno) reconstruir(ctx);
    escritaNoTurno = false;
    status(ctx);
  });
}
