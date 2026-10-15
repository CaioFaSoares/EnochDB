// EnochDB's ICM bridge to graphify. See docs/agents/graphify.md.
//
// The graph (`graphify-out/`) is DERIVED from the repository (A4): it is never a
// source of truth, never enters git and never decides anything. It serves the agent to find
// where to look before opening a file and to measure the reach of a change.
// Every failure here is a warning, never a block and never a verdict: without a graph, the ICM
// proceeds as before. Nothing here calls an LLM (`graphify update` is only AST/structure).
//
//   const G = await import(`${process.cwd()}/docs/_index/graphify.mjs`);
//   G.atualizar();                                   // rebuilds (incremental, ~2 s)
//   G.consultar("transactor", { sementes: ["lib/enoch/tx/CONTEXT.md"] });
//   G.impacto(["lib/enoch/tx.ex"]);                  // who depends on what changed
import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { RAIZ, carregarConfig } from "./jev-gate.mjs";

export const SAIDA = "graphify-out";
const GRAFO = join(RAIZ, SAIDA, "graph.json");
/** graphify exits with 0 even when it doesn't find the node; the only clue is the text. */
const SEM_NO = /^(No unique node match|No matching nodes)/;

export const config = () => carregarConfig().conducao.graphify;
export const ativo = () => config()?.ativo === true;

function graphify(args, timeoutS) {
  try {
    const saida = execFileSync("graphify", args, {
      cwd: RAIZ,
      encoding: "utf8",
      timeout: timeoutS * 1000,
      maxBuffer: 16 * 1024 * 1024,
      stdio: ["ignore", "pipe", "pipe"],
    });
    return { ok: true, saida };
  } catch (e) {
    if (e.code === "ENOENT") return { ok: false, motivo: "graphify is not on PATH" };
    if (e.killed || e.signal) return { ok: false, motivo: `graphify ${args[0]}: timed out (${timeoutS}s)` };
    const linha = `${e.stderr ?? ""}${e.stdout ?? ""}`.trim().split("\n").pop() || e.message;
    return { ok: false, motivo: `graphify ${args[0]} exited with ${e.status ?? "?"}: ${linha}` };
  }
}

/** State derived from the graph. `atual`: the commit it was built at is HEAD. */
export function estado() {
  if (!ativo()) return { ativo: false };
  const e = { ativo: true, existe: existsSync(GRAFO), atual: false, nos: null, commit: null, head: null };
  try {
    e.head = execFileSync("git", ["-C", RAIZ, "rev-parse", "HEAD"], { encoding: "utf8" }).trim();
  } catch {
    e.head = null;
  }
  if (!e.existe) return e;
  try {
    const g = JSON.parse(readFileSync(GRAFO, "utf8"));
    e.nos = g.nodes?.length ?? null;
    e.commit = g.built_at_commit ?? null;
    e.atual = e.commit !== null && e.commit === e.head;
  } catch {
    e.existe = false;
  }
  return e;
}

/**
 * Rebuilds the graph from the code and the docs (no LLM, incremental). graphify
 * serializes the calls with its own lock, so calling from two places is safe.
 * @returns {{ ok: boolean, motivo?: string, estado: object }}
 */
export function atualizar() {
  if (!ativo()) return { ok: false, motivo: "graphify disabled in jev-gates.json (conducao.graphify.ativo)", estado: { ativo: false } };
  const r = graphify(["update", "."], config().timeout_s);
  return { ok: r.ok, ...(r.ok ? {} : { motivo: r.motivo }), estado: estado() };
}

/**
 * Subgraph relevant to a question, already trimmed by the token budget.
 * `sementes`: node paths or labels; the ones the graph doesn't know are ignored.
 * @returns {string | null} `null` when there is no graph, node or answer.
 */
export function consultar(pergunta, { sementes = [], orcamento } = {}) {
  if (!ativo() || !existsSync(GRAFO)) return null;
  const cfg = config();
  const base = ["query", pergunta, "--budget", String(orcamento ?? cfg.orcamento_contexto_tokens)];
  const tenta = lista => {
    const r = graphify([...base, ...lista.flatMap(s => ["--seed", s])], cfg.timeout_s);
    const t = r.ok ? r.saida.trim() : "";
    return t && !/^No unique node match/m.test(t) && !SEM_NO.test(t) ? t : null;
  };
  // An unknown seed brings down the whole query: filter the known ones and, with none, only the question counts.
  const conhecidas = sementes.slice(0, cfg.max_sementes).filter(s => tenta([s]) !== null);
  return tenta(conhecidas);
}

/**
 * Nodes that depend on the given files (reverse traversal), without the files themselves.
 * Advisory: the graph is approximate, so the list is a hint for the reviewer, not proof.
 * @returns {{ no: string, relacao: string, onde: string }[]}
 */
export function impacto(arquivos) {
  if (!ativo() || !existsSync(GRAFO)) return [];
  const cfg = config();
  const proprios = new Set(arquivos);
  const vistos = new Map();
  for (const arq of arquivos) {
    const r = graphify(["affected", arq, "--depth", String(cfg.profundidade_impacto)], cfg.timeout_s);
    if (!r.ok || SEM_NO.test(r.saida.trim())) continue;
    for (const linha of r.saida.split("\n")) {
      const m = /^- (.+) \[([^\]]+)\] (.+?):L\d+$/.exec(linha);
      // A label equal to the path itself says no more than `onde` (it is the markdown file node).
      if (!m || proprios.has(m[3]) || m[1] === m[3]) continue;
      vistos.set(`${m[1]}|${m[3]}`, { no: m[1], relacao: m[2], onde: m[3] });
    }
  }
  return [...vistos.values()].slice(0, cfg.max_impacto);
}

/** A one-sentence line for the panel. */
export function resumo(e = estado()) {
  if (!e.ativo) return "graph: off";
  if (!e.existe) return "graph: absent (run `graphify update .`)";
  return `graph: ${e.nos ?? "?"} nodes · ${e.atual ? "at HEAD" : "behind HEAD (working tree may have more)"}`;
}
