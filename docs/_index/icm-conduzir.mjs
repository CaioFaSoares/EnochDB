// Conductor of the EnochDB ICM. See docs/agents/jev.md §Conduzir.
//
// One call returns: the current stage (derived in code), the gate verdict of that
// stage (Jev), a reading of each open issue (Jev) and, for the ready issues, a
// `task` package ready for the orchestrator to dispatch to roster subagents.
//
//   const c = await import(`${process.cwd()}/docs/_index/icm-conduzir.mjs`);
//   const p = await c.conduzir({ judge, judgeBatch }, { sprint: "s01-nucleo-enoch" });
//   console.log(c.painel(p));   // p.task is the argument of the `task` tool
//
// Code and the owner decide: the order of the stages, the next step, which roles
// are candidates and whether an issue is ready come from rules over the verdicts.
// Jev only gives probabilities (D5 of the handoff). The role suggestion is advisory
// and restricted to the candidates of the stage; below the minimum confidence it
// stays without a suggestion and the owner chooses. Nothing here writes to docs/ nor creates an issue.
import { execFileSync } from "node:child_process";
import { existsSync, readdirSync } from "node:fs";
import { join } from "node:path";
import {
  RAIZ,
  campo,
  carregarConfig,
  classificar,
  cortar,
  fatosDoSprint,
  lerRel,
  lote,
  registrar,
  rodar,
  sha,
  texto as textoGate,
} from "./jev-gate.mjs";
import * as grafo from "./graphify.mjs";

const NOME_BRANCO = /[^A-Za-z0-9]+/g;
export const camel = s => s.split(NOME_BRANCO).filter(Boolean).map(p => p[0].toUpperCase() + p.slice(1)).join("").slice(0, 32);
export const fim = s => s === "fechado" || s === "nao-aplicavel";

function papeisDoRoster(ids) {
  const dir = join(RAIZ, ".omp", "agents");
  const falhas = [];
  const papeis = [];
  for (const id of ids) {
    const arq = join(dir, `${id}.md`);
    if (!existsSync(arq)) {
      falhas.push(`role missing from the roster: ${id}`);
      continue;
    }
    const t = lerRel(`.omp/agents/${id}.md`);
    const descricao = campo(t, "description");
    if (!descricao) falhas.push(`role without description: ${id}`);
    else papeis.push({ id, descricao });
  }
  return { papeis, falhas };
}

function issuesAbertas() {
  try {
    const bruto = execFileSync(
      "gh",
      ["issue", "list", "--state", "open", "--limit", "50", "--json", "number,title,body,labels,url"],
      { cwd: RAIZ, encoding: "utf8", timeout: 30000 },
    );
    return { issues: JSON.parse(bruto) };
  } catch (e) {
    return { falha: `gh issue list failed: ${String(e.stderr || e.message).trim().split("\n")[0]}` };
  }
}

export const caminhosCitados = corpo =>
  [...new Set([...(corpo ?? "").matchAll(/`?((?:docs|lib|test|config|priv|examples)\/[\w./{}-]+\.\w+|CONTEXT\.md)`?/g)].map(m => m[1]))];

/** Current stage: the first one that is neither closed nor not applicable. `null` if all of them are. */
export function etapaAtual(fatos) {
  return fatos.etapas.find(e => !fim(e.status)) ?? null;
}

function perguntasDeIssue(cfgC, papeis, etapa) {
  const q = Object.fromEntries(
    cfgC.perguntas_issue.map(p => [p.id, { type: "bool", instructions: p.instrucoes }]),
  );
  if (papeis.length > 1) {
    q.papel = {
      type: "choice",
      instructions: `The issue is an item of stage ${etapa}. Which roster role is the most suitable to execute it?`,
      criteria: {
        ...Object.fromEntries(papeis.map(p => [p.id, p.descricao])),
        nenhum: "None of the roles above describes the work the issue asks for.",
      },
    };
  }
  return q;
}

function lerIssue(issue, resp, cfg, cfgC, papeis, avisos) {
  const faixa = cfg.faixa_incerta;
  const perguntas = {};
  const classes = [];
  for (const p of cfgC.perguntas_issue) {
    const valor = resp?.[p.id]?.bool;
    if (typeof valor !== "number") {
      avisos.push(`#${issue.number}: no answer for ${p.id}`);
      classes.push("achado");
      continue;
    }
    perguntas[p.id] = valor;
    if (p.ruim_se) classes.push(classificar(valor, p.ruim_se, faixa));
  }
  const prontidao = classes.includes("achado") ? "refinar" : classes.includes("incerto") ? "incerta" : "pronta";
  let papel = null;
  if (papeis.length === 1) papel = { id: papeis[0].id, confianca: null, origem: "single candidate of the stage" };
  else if (resp?.papel?.choice) {
    const { choice, confidence, probabilities } = resp.papel;
    const topo = probabilities?.[choice] ?? 0;
    if (choice !== "nenhum" && confidence >= cfgC.confianca_minima_papel && topo >= cfgC.confianca_minima_papel)
      papel = { id: choice, confianca: Number(confidence.toFixed(2)), origem: "jev" };
    else papel = { id: null, tentativa: choice, confianca: Number((confidence ?? 0).toFixed(2)), origem: "below the minimum confidence" };
  }
  return { numero: issue.number, titulo: issue.title, url: issue.url, perguntas, prontidao, papel };
}

/** Shared context of any ICM dispatch; a single home for the subagent rules. */
export function contextoCompartilhado(sprint, etapa) {
  return [
    "# Goal",
    `Sprint ${sprint}, stage ${etapa}. Each task is an issue of the repository tracker.`,
    "",
    "# Contract",
    "- Read before acting: `CONTEXT.md`, `docs/canon.md`, `docs/agents/README.md`, the contract of the stage in `docs/" + etapa + "/CONTEXT.md` and the ADRs that touch the area.",
    "- Use the glossary vocabulary. If the issue contradicts an ADR, expose the conflict and stop; do not rewrite a decision.",
    "- Reading roles do not write files: they return the result to whoever asked. Whoever writes only touches the files the orchestrator declared as theirs before the dispatch.",
    "- Evidence says how it was obtained: `leitura` or `execucao`. No unobserved verification.",
    "- Closing a stage, changing `status:` and publishing an issue are owner acts.",
    "- Jev questions and thresholds: `docs/agents/jev-gates.json`. Do not create others and do not edit them.",
    "- Before opening or grepping a raw file, use the graph: `graphify query \"<question>\"`, `graphify explain \"<node>\"` or `graphify affected \"<node>\"` (`graphify-out/graph.json`). The graph is derived and approximate: it points to where to look, and the evidence is still `arquivo:linha` read in the file.",
  ].join("\n");
}

function pacoteTask(plano, etapa) {
  const prontas = plano.issues.filter(i => i.prontidao === "pronta" && i.papel?.id);
  if (prontas.length === 0) return null;
  const contexto = contextoCompartilhado(plano.sprint, etapa);
  const tasks = prontas.map(i => {
    const caminhos = i.caminhos.length ? i.caminhos.map(c => `\`${c}\``).join(", ") : "none cited";
    return {
      agent: i.papel.id,
      name: camel(`Issue ${i.numero} ${i.papel.id.replace(/^\d+-/, "")}`),
      solutionSpace: "bounded issue with acceptance criteria; the approach stays open within the criteria",
      task: [
        "# Target",
        `Issue #${i.numero}: ${i.titulo}. Read the body with \`gh issue view ${i.numero}\` (cwd at the repository root); it was not copied here.`,
        `Paths cited in the issue (they exist): ${caminhos}.`,
        ...(i.grafo ? ["", "# Graph (graphify hint, derived; confirm in the file)", i.grafo] : []),
        "",
        "# Change",
        `Deliver only what issue #${i.numero} asks for, within stage ${etapa}. Files you may write: the ones the orchestrator declares in the dispatch; without a declared owner, do not edit.`,
        "",
        "# Acceptance",
        `Each acceptance criterion of issue #${i.numero} with the evidence (\`leitura\` or \`execucao\`) and what was left without proof.`,
      ].join("\n"),
    };
  });
  return { i: `Dispatching ${tasks.length} issue(s) of stage ${etapa}`, context: contexto, tasks };
}

/**
 * Conducting panel. `args`: { sprint, issues?: boolean (default true), gate?: boolean (default true) }.
 * Never throws on a judge, artifact or gh failure: it returns `bloqueios`.
 */
export async function conduzir(kernel, args = {}) {
  const { sprint } = args;
  if (!sprint) throw new Error("`sprint` is required");
  const cfg = carregarConfig();
  const cfgC = cfg.conducao;
  const fatos = fatosDoSprint(sprint);
  const atual = etapaAtual(fatos);
  const plano = {
    sprint,
    etapa: atual?.nome ?? null,
    etapas: fatos.etapas.map(e => ({ nome: e.nome, status: e.status, handovers: e.handovers })),
    bloqueios: [...fatos.falhas],
    gate: null,
    issues: [],
    proximo: [],
    modelo: cfg.modelo,
    calibrado: cfg.calibrado,
  };
  const atualizado = grafo.atualizar();
  plano.grafo = { resumo: grafo.resumo(atualizado.estado), ...(atualizado.ok || !atualizado.estado.ativo ? {} : { falha: atualizado.motivo }) };
  if (!atual) {
    plano.proximo.push("All the stages are closed or not applicable: the sprint is closed (derived). Nothing to conduct.");
    return plano;
  }

  // 1. Gate of the current stage, only when there is a handover to judge.
  const nomeGate = cfgC.gate_por_etapa[atual.nome];
  const handover = cfgC.handover_por_etapa[atual.nome];
  const g = cfg.gates[nomeGate];
  const alvos = Object.values(g.artefatos ?? {}).map(t => t.replaceAll("{sprint}", sprint));
  const faltam = alvos.filter(rel => lerRel(rel) === null);
  if (args.gate === false) plano.gate = { pulado: true };
  else if (faltam.length) plano.gate = { pulado: true, motivo: `missing ${faltam.map(f => f.split("/").pop()).join(", ")}` };
  else {
    const r = await rodar(kernel, nomeGate, { sprint });
    // Receipt only for a real verdict: a block is not a verdict (see freshness in jev-gate.mjs).
    const recibo = r.falhas.length ? { gravado: false } : registrar(r, { etapa: atual.nome });
    plano.gate = { nome: nomeGate, veredito: r.veredito, recibo: r.recibo, registrado: recibo.gravado, texto: textoGate(r), achados: r.achados.length, falhas: r.falhas };
    plano.bloqueios.push(...r.falhas.map(f => `gate ${nomeGate}: ${f}`));
  }

  // 2. Open issues read by Jev, with the candidate roles of the stage.
  if (args.issues !== false) {
    const { papeis, falhas } = papeisDoRoster(cfgC.papeis_por_etapa[atual.nome] ?? []);
    plano.bloqueios.push(...falhas);
    const lista = issuesAbertas();
    if (lista.falha) plano.bloqueios.push(lista.falha);
    else if (papeis.length === 0) plano.bloqueios.push(`no candidate roles for ${atual.nome}`);
    else if (lista.issues.length) {
      const trunc = [];
      const states = Object.fromEntries(
        lista.issues.map(i => [String(i.number), {
          etapa: atual.nome,
          estado_das_etapas: Object.fromEntries(fatos.etapas.map(e => [e.nome, e.status])),
          titulo: i.title,
          rotulos: i.labels.map(l => l.name),
          corpo: cortar(i.body ?? "", cfg.limite_estado_chars, trunc, `issue #${i.number}`),
        }]),
      );
      const { ok, erro } = await lote(kernel, states, perguntasDeIssue(cfgC, papeis, atual.nome), `issues ${sprint}`);
      for (const [k, msg] of Object.entries(erro)) plano.bloqueios.push(`issue #${k}: judge failed: ${msg}`);
      const avisos = [];
      for (const i of lista.issues) {
        if (!ok[String(i.number)]) continue;
        const lida = lerIssue(i, ok[String(i.number)], cfg, cfgC, papeis, avisos);
        lida.caminhos = caminhosCitados(i.body).filter(c => !c.includes("{") && existsSync(join(RAIZ, c)));
        if (lida.prontidao === "pronta" && lida.papel?.id) lida.grafo = grafo.consultar(i.title, { sementes: lida.caminhos });
        lida.hash = sha(`${i.title}\n${i.body ?? ""}`).slice(0, 12);
        plano.issues.push(lida);
      }
      plano.bloqueios.push(...avisos);
      plano.truncamentos = trunc;
    }
  }

  // 3. Next step: a rule over the facts, never a choice of Jev.
  if (fatos.falhas.length) plano.proximo.push("Fix the state inconsistencies listed in bloqueios before anything else.");
  if (plano.gate?.pulado && plano.gate.motivo) plano.proximo.push(`Produce handovers/${handover} of stage ${atual.nome} (contract: docs/${atual.nome}/CONTEXT.md).`);
  else if (plano.gate?.achados) plano.proximo.push(`Read the ${plano.gate.achados} finding(s) of gate ${nomeGate} in the artifact and resolve or record each one.`);
  else if (plano.gate?.veredito === "sem_achados") plano.proximo.push(`Take the receipt ${plano.gate.recibo} to the owner for the human gate of ${atual.nome}; sem_achados is not an approval.`);
  const prontas = plano.issues.filter(i => i.prontidao === "pronta");
  const refinar = plano.issues.filter(i => i.prontidao !== "pronta");
  const comPapel = prontas.filter(i => i.papel?.id);
  const semPapel = prontas.filter(i => !i.papel?.id);
  if (refinar.length) plano.proximo.push(`Refine with the owner: ${refinar.map(i => `#${i.numero} (${i.prontidao})`).join(", ")}.`);
  if (comPapel.length) plano.proximo.push(`Ask for the owner's go and declare the owner of each file before dispatching: ${comPapel.map(i => `#${i.numero}`).join(", ")}.`);
  if (semPapel.length) plano.proximo.push(`Ready without a suggested role (${semPapel.map(i => `#${i.numero}`).join(", ")}): the owner chooses the role or the orchestrator executes; there is no dispatch assembled.`);
  if (atual.nome === "05_implement") plano.proximo.push("Implement the issues of the sprint in a loop with verification: `/icm implement` (the standalone dispatch stays off in this stage).");
  plano.task = atual.nome === "05_implement" ? null : pacoteTask(plano, atual.nome);
  return plano;
}

/** Short text for the human and for the orchestrator. */
export function painel(p) {
  const l = [`ICM · ${p.sprint} · current stage: ${p.etapa ?? "nenhuma"} (derived) · ${p.modelo} · calibrated: ${p.calibrado}`];
  l.push(p.etapas.map(e => `${e.nome.slice(0, 2)}:${e.status}`).join("  "));
  if (p.grafo) l.push(p.grafo.falha ? `WARNING  ${p.grafo.resumo}; update failed: ${p.grafo.falha}` : p.grafo.resumo);
  for (const b of p.bloqueios) l.push(`BLOCKED  ${b}`);
  if (p.gate) {
    if (p.gate.pulado) l.push(`gate: skipped${p.gate.motivo ? ` (${p.gate.motivo})` : ""}`);
    else l.push("", p.gate.texto);
  }
  if (p.issues.length) {
    l.push("", "open issues (Jev reading; advisory):");
    for (const i of p.issues) {
      const papel = i.papel?.id ? `${i.papel.id}${i.papel.confianca != null ? ` (${i.papel.confianca})` : ""}` : `no suggestion${i.papel?.tentativa ? ` [${i.papel.tentativa} ${i.papel.confianca}]` : ""}`;
      const q = Object.entries(i.perguntas).map(([k, v]) => `${k}=${v.toFixed(2)}`).join(" ");
      l.push(`  #${i.numero} ${i.prontidao.toUpperCase().padEnd(7)} ${papel} · ${i.titulo.slice(0, 70)}`, `      ${q}`);
    }
  }
  if (p.proximo.length) l.push("", "next:", ...p.proximo.map((x, n) => `  ${n + 1}. ${x}`));
  if (p.task) l.push("", `dispatch ready: p.task (${p.task.tasks.length} task(s): ${p.task.tasks.map(t => `${t.name}→${t.agent}`).join(", ")})`);
  return l.join("\n");
}

/** Lists the existing sprints, for the command with no argument. */
export function sprints() {
  const d = join(RAIZ, "docs/_sprints");
  return existsSync(d) ? readdirSync(d, { withFileTypes: true }).filter(e => e.isDirectory()).map(e => e.name).sort() : [];
}
