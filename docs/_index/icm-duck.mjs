// Backlog of `/icm duck`. See docs/_backlog/README.md and docs/agents/jev.md §Duck.
//
// The conversation with the rubberduck explores a doubt; what is worth keeping
// becomes a file in docs/_backlog/. This module only validates and writes; who
// talks and decides what goes in is the orchestrator with the owner.
//
//   const B = await import(`${process.cwd()}/docs/_index/icm-duck.mjs`);
//   const v = await B.prever({ judge, judgeBatch }, { titulo, pergunta, evidencias, contradicoes, em_aberto });
//   console.log(B.texto(v));          // the owner reads before any write
//   B.gravar(v);                      // only after the owner's ok; refuses if there is a block
//
// Guarantees in code: every `arquivo:linha` anchor is opened and the cited excerpt
// must be in the line; an item without an anchor is written as an idea, never as a
// fact; the suggested epic is advisory (Jev, below the minimum confidence it stays
// `—`); positioning in a sprint is moving the file, an owner act.
import { existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { join, resolve, sep } from "node:path";
import { RAIZ, campo, carregarConfig, cortar, lote, perguntasBool } from "./jev-gate.mjs";

const ALEPH = resolve(RAIZ, "..");
const DIR = "docs/_backlog";
const semAcento = s => s.normalize("NFD").replace(/[\u0300-\u036f]/g, "");
const slug = s => {
  const base = semAcento(s).toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
  if (base.length <= 48) return base;
  const corte = base.slice(0, 48);
  return corte.slice(0, Math.max(corte.lastIndexOf("-"), 16));
};
const norm = s => semAcento(s).toLowerCase().replace(/\s+/g, " ").trim();

function resolverAncora({ ancora, trecho }) {
  const m = /^(.+):(\d+)$/.exec(ancora ?? "");
  if (!m) return `invalid anchor (expected arquivo:linha): ${ancora}`;
  const abs = resolve(RAIZ, m[1]);
  if (abs !== ALEPH && !abs.startsWith(RAIZ + sep) && !abs.startsWith(ALEPH + sep)) return `anchor outside ${ALEPH}: ${ancora}`;
  if (abs.split(sep).includes(".git")) return `anchor in .git: ${ancora}`;
  if (!existsSync(abs)) return `anchor file does not exist: ${ancora}`;
  const linhas = readFileSync(abs, "utf8").split("\n");
  const n = Number(m[2]);
  if (n < 1 || n > linhas.length) return `line outside the file (${linhas.length} lines): ${ancora}`;
  if (!trecho || !norm(linhas[n - 1]).includes(norm(trecho))) return `the excerpt is not in line ${n} of ${m[1]}: "${trecho}"`;
  return null;
}

function epicosAbertos() {
  const dir = join(RAIZ, "docs/epicos");
  if (!existsSync(dir)) return [];
  return readdirSync(dir)
    .filter(f => /^e\d+-.*\.md$/.test(f))
    .map(f => {
      const t = readFileSync(join(dir, f), "utf8");
      return { id: campo(t, "id") ?? f.replace(/\.md$/, ""), titulo: campo(t, "titulo") ?? "", status: campo(t, "status") };
    })
    .filter(e => e.status === "aberto");
}

/** Sprints without any started stage: candidates to receive the item. Derived from the sheets. */
export function sprintsNaoIniciadas() {
  const d = join(RAIZ, "docs/_sprints");
  if (!existsSync(d)) return [];
  return readdirSync(d, { withFileTypes: true })
    .filter(e => e.isDirectory())
    .map(e => e.name)
    .filter(nome => {
      const etapas = readdirSync(join(d, nome), { withFileTypes: true }).filter(x => x.isDirectory());
      return etapas.length > 0 && etapas.every(x => campo(readFileSync(join(d, nome, x.name, "CONTEXT.md"), "utf8"), "status") === "vazio");
    });
}

function proximoId() {
  const dir = join(RAIZ, DIR);
  const nums = existsSync(dir) ? readdirSync(dir).map(f => /^B(\d+)-/.exec(f)?.[1]).filter(Boolean).map(Number) : [];
  return `B${String((nums.length ? Math.max(...nums) : 0) + 1).padStart(2, "0")}`;
}

function renderizar(v) {
  const l = [
    "---",
    `id: ${v.id}`,
    `titulo: ${v.titulo}`,
    "origem: duck",
    `aberta_em: ${v.data}`,
    `epico_sugerido: ${v.epico ?? "—"} # advisory (Jev${v.epico_confianca != null ? `, confidence ${v.epico_confianca}` : ""}); whoever positions it is the owner`,
    ...(v.evidencias.length ? [] : ["sem_ancora: true # idea, not fact"]),
    "---",
    "",
    `# ${v.id} — ${v.titulo}`,
    "",
    "## Question",
    "",
    v.pergunta,
    "",
  ];
  if (v.resumo) l.push("## What is known", "", v.resumo, "");
  if (v.evidencias.length) {
    l.push("## Anchors", "");
    for (const e of v.evidencias) l.push(`- \`${e.ancora}\` — ${e.trecho}`);
    l.push("");
  }
  if (v.contradicoes.length) l.push("## Contradictions", "", ...v.contradicoes.map(c => `- ${c}`), "");
  if (v.em_aberto.length) l.push("## Open", "", ...v.em_aberto.map(c => `- ${c}`), "");
  l.push(
    "## How to position",
    "",
    "Move this file to `docs/_sprints/<sprint>/01_grilling/inputs/` of a sprint that has not started yet (`git mv`). Leaving here is the positioning; nobody declares the destination sprint inside the file.",
    "",
  );
  return l.join("\n");
}

/**
 * Validates and prepares the item without writing anything. `args`: { titulo, pergunta, resumo?, evidencias?, contradicoes?, em_aberto? }.
 * `evidencias`: [{ ancora: "arquivo:linha", trecho }]. Returns `bloqueios` if something does not hold.
 */
export async function prever(kernel, args) {
  const cfg = carregarConfig();
  const cfgB = cfg.conducao.backlog;
  const { titulo, pergunta, resumo = "", evidencias = [], contradicoes = [], em_aberto = [] } = args ?? {};
  const v = { id: proximoId(), titulo, pergunta, resumo, evidencias, contradicoes, em_aberto, data: new Date().toISOString().slice(0, 10), bloqueios: [], achados: [], epico: null, epico_confianca: null, truncamentos: [] };
  if (!titulo?.trim()) v.bloqueios.push("no title");
  if (!pergunta?.trim()) v.bloqueios.push("no question");
  if (v.bloqueios.length) return v;
  for (const e of evidencias) {
    const erro = resolverAncora(e);
    if (erro) v.bloqueios.push(erro);
  }
  v.arquivo = `${DIR}/${v.id}-${slug(titulo)}.md`;
  if (existsSync(join(RAIZ, v.arquivo))) v.bloqueios.push(`already exists: ${v.arquivo}`);
  if (v.bloqueios.length) return v;
  v.md = renderizar(v);

  const estado = cortar(v.md, cfg.limite_estado_chars, v.truncamentos, v.arquivo);
  const epicos = epicosAbertos();
  const questions = perguntasBool(cfgB.perguntas);
  if (epicos.length) {
    questions.epico = {
      type: "choice",
      instructions: "Which open epic does this backlog item belong to?",
      criteria: { ...Object.fromEntries(epicos.map(e => [e.id, e.titulo])), nenhum: "None of the open epics describes the subject of the item." },
    };
  }
  const { ok, erro } = await lote(kernel, { item: { item: estado } }, questions, `backlog ${v.id}`);
  for (const m of Object.values(erro)) v.bloqueios.push(`judge failed: ${m}`);
  const r = ok.item;
  if (r) {
    for (const q of cfgB.perguntas) {
      const x = r[q.id]?.bool;
      if (typeof x !== "number") {
        v.bloqueios.push(`no answer for ${q.id}`);
        continue;
      }
      const [baixo, alto] = cfg.faixa_incerta;
      const ruim = q.ruim_se === "alto" ? x >= alto : x <= baixo;
      const incerto = x > baixo && x < alto;
      if (ruim || incerto) v.achados.push({ pergunta: q.id, valor: Number(x.toFixed(2)), classe: ruim ? "achado" : "incerto" });
    }
    if (r.epico?.choice && r.epico.choice !== "nenhum" && r.epico.confidence >= cfgB.confianca_minima_epico && (r.epico.probabilities?.[r.epico.choice] ?? 0) >= cfgB.confianca_minima_epico) {
      v.epico = r.epico.choice;
      v.epico_confianca = Number(r.epico.confidence.toFixed(2));
      v.md = renderizar(v);
    }
  }
  v.candidatas = sprintsNaoIniciadas();
  return v;
}

/** Writes the item. Refuses if `prever` returned a block. Only after the owner's ok. */
export function gravar(v) {
  if (v.bloqueios?.length) throw new Error(`I do not write with a block: ${v.bloqueios.join("; ")}`);
  const abs = join(RAIZ, v.arquivo);
  if (existsSync(abs)) throw new Error(`already exists: ${v.arquivo}`);
  mkdirSync(join(RAIZ, DIR), { recursive: true });
  writeFileSync(abs, v.md);
  return { arquivo: v.arquivo };
}

export function texto(v) {
  const l = [`backlog · ${v.id ?? "—"} · ${v.titulo ?? "(no title)"}`];
  for (const b of v.bloqueios) l.push(`BLOCKED  ${b}`);
  for (const a of v.achados) l.push(`${a.classe === "achado" ? "FINDING  " : "UNCERTAIN"} ${a.pergunta} = ${a.valor.toFixed(2)}`);
  if (!v.bloqueios.length) {
    l.push(`file: ${v.arquivo}`, `anchors verified in code: ${v.evidencias.length}${v.evidencias.length ? "" : " (written as an idea, without fact)"}`, `suggested epic: ${v.epico ?? "—"}${v.epico_confianca != null ? ` (${v.epico_confianca})` : ""}`);
    l.push(`sprints not yet started: ${v.candidatas?.length ? v.candidatas.join(", ") : "nenhuma (create one via PROCESS.md, \"Abrir uma sprint\")"}`);
  }
  return l.join("\n");
}
