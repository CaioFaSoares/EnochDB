// EnochDB's ICM implementation loop (`/icm implement`). See docs/agents/jev.md §Implement.
//
// One call to `passo` runs ONE iteration of ONE issue: it dispatches the slice's
// owner, measures what they actually changed, runs the verification, asks Jev
// whether each acceptance criterion was covered with observed execution, and
// records the result. The orchestrator calls `passo` until it returns `fim` or `bloqueado`.
// Progress is derived from `05_implement/handovers/jev.jsonl` (A4): whoever resumes
// the session continues from where the file stopped.
//
//   const I = await import(`${process.cwd()}/docs/_index/icm-implementar.mjs`);
//   const p = await I.plano({ sprint });          // read-only: order, criteria, go proposal
//   I.registrarGo({ sprint, itens: [...] });      // only after the owner's go
//   const r = await I.passo({ judge, judgeBatch, agent }, { sprint });
//   const f = await I.fechar({ judge, judgeBatch }, { sprint });  // when `fim`
//
// Code decides: order, file ownership, scope actually written, verification
// result, iteration limit and the final verdict. Jev only gives the probability
// of each criterion being covered by observed execution.
// A judge, verifier, subagent or scope failure is `bloqueada`,
// never `ok`. Nothing here commits, closes an issue, changes `status:` or edits
// what is in `implementacao.protegidos`.
import { execFileSync } from "node:child_process";
import { appendFileSync, existsSync, lstatSync, readFileSync, readlinkSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import {
  RAIZ,
  carregarConfig,
  classificar,
  cortar,
  fatosDoSprint,
  lerRel,
  lote,
  perguntasBool,
  registrar,
  rodar,
  sha,
  texto as textoGate,
} from "./jev-gate.mjs";
import { camel, caminhosCitados, contextoCompartilhado, etapaAtual } from "./icm-conduzir.mjs";
import * as grafo from "./graphify.mjs";

const MARCA = "<!-- gerado por docs/_index/icm-implementar.mjs a partir de handovers/jev.jsonl -->";
const CHECK = /^\s*[-*]\s+\[[ xX]\]\s+(.*)$/;

export const RELATORIO = {
  type: "object",
  required: ["arquivos", "criterios", "comandos", "bloqueios"],
  properties: {
    arquivos: {
      type: "array",
      items: { type: "object", required: ["caminho", "mudanca"], properties: { caminho: { type: "string" }, mudanca: { type: "string" } } },
    },
    criterios: {
      type: "array",
      items: {
        type: "object",
        required: ["criterio", "atendimento", "evidencia"],
        properties: {
          criterio: { type: "string" },
          atendimento: { type: "string" },
          evidencia: { type: "string", enum: ["execucao", "leitura", "nenhuma"] },
          comando: { type: "string" },
        },
      },
    },
    comandos: {
      type: "array",
      items: { type: "object", required: ["comando", "resultado"], properties: { comando: { type: "string" }, resultado: { type: "string" } } },
    },
    bloqueios: { type: "array", items: { type: "string" }, description: "Only a real blocker: something that prevents delivering the slice and that you cannot resolve. Must be empty when nothing blocks." },
    notas: { type: "array", items: { type: "string" }, description: "Observations, warnings and pointers for the owner; they never become a blocker." },
  },
};

const rel05 = (sprint, arq) => `docs/_sprints/${sprint}/05_implement/handovers/${arq}`;
const git = (...a) => execFileSync("git", ["-C", RAIZ, ...a], { encoding: "utf8" });

function registros(sprint) {
  const t = lerRel(rel05(sprint, "jev.jsonl")) ?? "";
  return t.split("\n").filter(Boolean).map(l => JSON.parse(l));
}

function anexar(sprint, obj) {
  appendFileSync(join(RAIZ, rel05(sprint, "jev.jsonl")), `${JSON.stringify({ em: new Date().toISOString(), ...obj })}\n`);
}

function secao(corpo, reTitulo) {
  const linhas = (corpo ?? "").split("\n");
  const re = new RegExp(reTitulo, "i");
  const ini = linhas.findIndex(l => re.test(l));
  if (ini < 0) return "";
  let f = ini + 1;
  while (f < linhas.length && !/^#{1,3}\s/.test(linhas[f])) f++;
  return linhas.slice(ini + 1, f).join("\n");
}

const dentro = (caminho, dono) => dono.some(d => caminho === d || (d.endsWith("/") && caminho.startsWith(d)));

function caminhoValido(c) {
  return typeof c === "string" && c.length > 0 && !c.startsWith("/") && !c.split("/").includes("..") && !c.includes("\0");
}

/**
 * Why a blocked issue can be reopened with `reabrir: [N]` (owner-only act): `"prosa"` when
 * the block came only from the report's `bloqueios` field, `"incerto"` when it came only from
 * uncertain Jev findings that exhausted the iterations. It never covers a contract violation
 * (HEAD, owner, protected path), a Jev failure or a verification failure. `null` = not reopenable.
 */
function reabravel(u) {
  if (!u || u.veredito !== "bloqueada") return null;
  const motivos = u.motivos ?? [];
  if (!motivos.length) return null;
  if (!(u.testes ?? []).every(t => t.estado !== "executado" || t.codigo === 0)) return null;
  if (motivos.every(m => m.startsWith("subagente bloqueou:"))) return "prosa";
  const soIncerto = (u.achados ?? []).length > 0 && u.achados.every(a => a.classe === "incerto");
  const motivosSoIncerto = motivos.every(m => m.startsWith("esgotou ") || /^.+: [a-z_]+=[\d.]+ \([a-z]+\)$/.test(m));
  return soIncerto && motivosSoIncerto ? "incerto" : null;
}

/** State derived for each issue of the sprint from the records. `reabrir` is an owner-only act. */
function estadoDe(regs, numero, reabrir = []) {
  const doIssue = [...regs].reverse().filter(r => r.tipo === "implementacao_iteracao" && r.issue === numero);
  const ultima = doIssue[0];
  if (!ultima) return { estado: "pendente", iteracoes: 0, ultima: null };
  const origem = reabrir.includes(numero) ? reabravel(ultima) : null;
  if (origem) {
    // The reopening starts a new iteration quota; the history stays in `implementacao_reabertura`.
    return { estado: "reaberta", iteracoes: 0, ultima: doIssue[1] ?? null, reaberta: ultima, origem };
  }
  const estado = ultima.veredito === "ok" ? "ok" : ultima.veredito === "bloqueada" ? "bloqueada" : "em-curso";
  return { estado, iteracoes: ultima.iteracao, ultima };
}

function carregarIssues(sprint, numerosArg) {
  let numeros = numerosArg;
  if (!numeros) {
    const t = lerRel(`docs/_sprints/${sprint}/04_tickets/handovers/tickets.md`);
    if (t === null) return { falha: "no 04_tickets/handovers/tickets.md: the sprint's issue list is the `#N` cited in it (or pass `issues`)" };
    numeros = [...new Set([...t.matchAll(/(?<![\w/])#(\d+)\b/g)].map(m => Number(m[1])))];
    if (numeros.length === 0) return { falha: "tickets.md cites no issue as `#N`; record the number of each published issue" };
  }
  let todas;
  try {
    todas = JSON.parse(
      execFileSync("gh", ["issue", "list", "--state", "all", "--limit", "200", "--json", "number,title,body,state,url"], {
        cwd: RAIZ, encoding: "utf8", timeout: 30000,
      }),
    );
  } catch (e) {
    return { falha: `gh issue list failed: ${String(e.stderr || e.message).trim().split("\n")[0]}` };
  }
  const porNumero = new Map(todas.map(i => [i.number, i]));
  const ausentes = numeros.filter(n => !porNumero.has(n));
  if (ausentes.length) return { falha: `issues that do not exist in the tracker: ${ausentes.map(n => `#${n}`).join(", ")}` };
  return { numeros, porNumero };
}

/**
 * Read-only plan. Returns the order (topological by declared dependencies),
 * the criteria extracted in code, the derived state and a go proposal.
 */
export async function plano({ sprint, issues: numerosArg, reabrir = [] }) {
  const cfg = carregarConfig();
  const cfgI = cfg.conducao.implementacao;
  const p = { sprint, bloqueios: [], issues: [], proxima: null, go: null, max_iteracoes: cfgI.max_iteracoes };
  const fatos = fatosDoSprint(sprint);
  const atual = etapaAtual(fatos);
  if (fatos.falhas.length) p.bloqueios.push(...fatos.falhas);
  if (!atual || atual.nome !== "05_implement") {
    p.bloqueios.push(`the current step is ${atual?.nome ?? "none"}; the loop only runs in 05_implement (04_tickets must be closed or not applicable)`);
    return p;
  }
  const carregadas = carregarIssues(sprint, numerosArg);
  if (carregadas.falha) {
    p.bloqueios.push(carregadas.falha);
    return p;
  }
  const regs = registros(sprint);
  p.go = [...regs].reverse().find(r => r.tipo === "implementacao_go") ?? null;
  const noSprint = new Set(carregadas.numeros);
  const itens = carregadas.numeros.map(n => {
    const i = carregadas.porNumero.get(n);
    const criterios = secao(i.body, cfgI.secao_criterios).split("\n").map(l => CHECK.exec(l)?.[1].trim()).filter(Boolean);
    const deps = [...new Set([...secao(i.body, cfgI.secao_dependencias).matchAll(/(?<![\w/])#(\d+)\b/g)].map(m => Number(m[1])))];
    const go = p.go?.itens?.find(x => x.numero === n);
    return {
      numero: n,
      titulo: i.title,
      aberta: i.state === "OPEN",
      criterios,
      deps,
      caminhos: caminhosCitados(i.body).filter(c => !c.includes("{") && existsSync(join(RAIZ, c))),
      papel: go?.papel ?? cfgI.papel_padrao,
      dono: go?.dono ?? [],
      ...estadoDe(regs, n, reabrir),
      ...(i.state === "CLOSED" && !regs.some(r => r.tipo === "implementacao_iteracao" && r.issue === n) ? { estado: "fechada" } : {}),
    };
  });
  // stable topological order by number; a cycle and an open external dependency are blockers
  const porNum = new Map(itens.map(i => [i.numero, i]));
  const ordem = [];
  const visto = new Set();
  const pilha = new Set();
  const visitar = i => {
    if (visto.has(i.numero)) return;
    if (pilha.has(i.numero)) {
      p.bloqueios.push(`dependency cycle involving #${i.numero}`);
      return;
    }
    pilha.add(i.numero);
    for (const d of i.deps) if (porNum.has(d)) visitar(porNum.get(d));
    pilha.delete(i.numero);
    visto.add(i.numero);
    ordem.push(i);
  };
  [...itens].sort((a, b) => a.numero - b.numero).forEach(visitar);
  for (const i of ordem) {
    if (i.criterios.length === 0) {
      i.bloqueio = "issue with no extractable acceptance criteria (`- [ ]` in the criteria section)";
    }
    const externas = i.deps.filter(d => !noSprint.has(d));
    for (const d of externas) {
      const s = carregadas.porNumero.get(d)?.state;
      if (s === undefined) i.bloqueio = `depends on #${d}, which is neither in the sprint nor queried; pass it in \`issues\` or resolve it`;
      else if (s === "OPEN") i.bloqueio = `depends on #${d}, open and outside the sprint`;
    }
  }
  const concluida = n => ["ok", "fechada"].includes(porNum.get(n)?.estado) || (!noSprint.has(n) && carregadas.porNumero.get(n)?.state === "CLOSED");
  for (const i of ordem) {
    if (["ok", "bloqueada", "fechada"].includes(i.estado)) continue;
    if (i.bloqueio) continue;
    const dep = i.deps.find(d => porNum.get(d)?.estado === "bloqueada" || porNum.get(d)?.bloqueio);
    if (dep) {
      i.bloqueio = `depends on #${dep}, which is ${porNum.get(dep).estado === "bloqueada" ? "bloqueada" : "blocked by dependency or criterion"}`;
      continue;
    }
    if (i.deps.every(concluida) && !p.proxima) p.proxima = i;
  }
  p.issues = ordem;
  p.proposta = ordem.map(i => ({
    numero: i.numero,
    papel: i.papel,
    dono: i.dono.length ? i.dono : [...new Set(i.caminhos.filter(c => !dentro(c, cfgI.protegidos)).map(c => c.replace(/[^/]+$/, "")).filter(Boolean))],
  }));
  return p;
}

/** Records the owner's go: one role and one path owner per issue. Only after the owner confirms. */
export function registrarGo({ sprint, itens, max_iteracoes }) {
  const cfgI = carregarConfig().conducao.implementacao;
  if (!itens?.length) throw new Error("go with no items");
  const vistos = new Set();
  for (const it of itens) {
    if (!Number.isInteger(it.numero) || vistos.has(it.numero)) throw new Error(`invalid or repeated issue: ${it.numero}`);
    vistos.add(it.numero);
    if (!it.papel || !existsSync(join(RAIZ, ".omp", "agents", `${it.papel}.md`))) throw new Error(`#${it.numero}: role absent from the roster: ${it.papel}`);
    if (!it.dono?.length) throw new Error(`#${it.numero}: no file owner; declare at least one path`);
    for (const c of it.dono) {
      if (!caminhoValido(c)) throw new Error(`#${it.numero}: invalid path: ${c}`);
      if (dentro(c, cfgI.protegidos) || cfgI.protegidos.some(p => p.startsWith(c))) throw new Error(`#${it.numero}: a protected path cannot be owned: ${c}`);
    }
  }
  const max = max_iteracoes ?? cfgI.max_iteracoes;
  anexar(sprint, { tipo: "implementacao_go", itens, max_iteracoes: max });
  return { itens: itens.length, max_iteracoes: max };
}

function assinatura(abs) {
  if (!existsSync(abs) && !lstatSync(abs, { throwIfNoEntry: false })) return "removed";
  const s = lstatSync(abs);
  if (s.isSymbolicLink()) return `link:${readlinkSync(abs)}`;
  if (s.isDirectory()) return "directory";
  return sha(readFileSync(abs));
}

function instantaneo(cfgI) {
  const util = lista => lista.filter(c => !dentro(c, cfgI.ignorados));
  const lista = util(git("ls-files", "-m", "-o", "--exclude-standard", "-z").split("\0").filter(Boolean));
  const removidos = new Set(util(git("ls-files", "-d", "-z").split("\0").filter(Boolean)));
  const mapa = {};
  for (const c of new Set([...lista, ...removidos])) {
    const abs = join(RAIZ, c);
    mapa[c] = assinatura(abs);
  }
  return { head: git("rev-parse", "HEAD").trim(), mapa };
}

const diferenca = (a, b) =>
  [...new Set([...Object.keys(a.mapa), ...Object.keys(b.mapa)])].filter(c => a.mapa[c] !== b.mapa[c]).sort();

function verificar(cfgI) {
  const resultados = [];
  for (const v of cfgI.verificacao) {
    if (v.requer && !existsSync(join(RAIZ, v.requer))) {
      resultados.push({ comando: v.comando, estado: "sem_verificador", motivo: `${v.requer} does not exist` });
      continue;
    }
    try {
      const saida = execFileSync("sh", ["-c", v.comando], {
        cwd: RAIZ, encoding: "utf8", timeout: cfgI.timeout_verificacao_s * 1000, maxBuffer: 64 * 1024 * 1024, stdio: ["ignore", "pipe", "pipe"],
      });
      resultados.push({ comando: v.comando, estado: "executado", codigo: 0, saida: saida.slice(-cfgI.limite_saida_chars) });
    } catch (e) {
      const saida = `${e.stdout ?? ""}${e.stderr ?? ""}`.slice(-cfgI.limite_saida_chars);
      if (e.status === 127 || e.code === "ENOENT") resultados.push({ comando: v.comando, estado: "sem_verificador", motivo: `command unavailable: ${saida.trim().split("\n").pop() || e.message}` });
      else if (e.killed || e.signal) resultados.push({ comando: v.comando, estado: "sem_verificador", motivo: `timed out (${cfgI.timeout_verificacao_s}s)` });
      else resultados.push({ comando: v.comando, estado: "executado", codigo: e.status ?? 1, saida });
    }
  }
  return resultados;
}

function briefing(p, issue, feedback, cfgI, pista) {
  const caminhos = issue.caminhos.length ? issue.caminhos.map(c => `\`${c}\``).join(", ") : "none cited";
  const verifs = cfgI.verificacao.map(v => `\`${v.comando}\``).join(", ");
  const partes = [
    contextoCompartilhado(p.sprint, "05_implement"),
    "",
    "# Target",
    `Issue #${issue.numero}: ${issue.titulo}. Read the body with \`gh issue view ${issue.numero}\` (cwd at the repository root); it was not copied here. The acceptance criteria section has ${issue.criterios.length} item(s).`,
    `Paths cited in the issue (they exist): ${caminhos}.`,
    `You own **only** these paths: ${issue.dono.map(d => `\`${d}\``).join(", ")}. Writing outside them, committing or editing \`${cfgI.protegidos.join("`, `")}\` invalidates the iteration.`,
    ...(pista ? ["", "# Graph (graphify hint, derived; confirm in the file)", pista] : []),
    "",
    "# Change",
    `Deliver only what issue #${issue.numero} asks for. Test first when there is a seam. Do not add a dependency or swap a tool. Only return in \`bloqueios\` what really **blocks** the slice; nothing blocked is \`bloqueios: []\`. Observations, warnings and pointers go in \`notas\`. Do not commit.`,
    `The orchestrator runs ${verifs} after you, but run whatever the criterion requires and report the real command and result.`,
    "",
    "# Acceptance",
    `Return the structured report: \`arquivos\` touched, \`criterios\` (one item per acceptance criterion, in the issue's order, with the criterion text, how it was met and the evidence \`execucao\`, \`leitura\` or \`nenhuma\`), \`comandos\` executed with the observed result, \`bloqueios\` (empty array when nothing blocks) and \`notas\` (observations and warnings).`,
  ];
  if (feedback) partes.push("", "# Previous iteration failed", feedback);
  return partes.join("\n");
}

const MOTIVO = {
  coberto_com_execucao: "no recorded execution with an observed result covering the criterion",
  so_leitura: "the criterion has only a code or document read as proof",
  alega_sem_provar: "the report claims it is ready with no command and result",
  declara_execucao: "the report records no executed command with a result",
};

async function avaliar(kernel, cfg, issue, relatorio, verificacao, alterados) {
  const faixa = cfg.faixa_incerta;
  const execucao = verificacao.map(v => ({ comando: v.comando, estado: v.estado, codigo: v.codigo ?? null, motivo: v.motivo ?? null, saida_final: v.saida ?? null }));
  const base = { relatorio_do_subagente: relatorio, verificacao_executada_pelo_orquestrador: execucao, arquivos_alterados_medidos: alterados };
  const gi = cfg.gates.implementacao;
  const states = Object.fromEntries(issue.criterios.map((c, k) => [`c${k + 1}`, { criterio_de_aceite: c, ...base }]));
  const falhas = [];
  const achados = [];
  const [porCrit, global] = await Promise.all([
    lote(kernel, states, perguntasBool(gi.perguntas), `implementacao #${issue.numero} criteria`),
    lote(kernel, { g: base }, perguntasBool(gi.perguntas_globais), `implementacao #${issue.numero} global`),
  ]);
  for (const [k, m] of [...Object.entries(porCrit.erro), ...Object.entries(global.erro)]) falhas.push(`judge failed (${k}): ${m}`);
  const ler = (chave, resp, perguntas) => {
    for (const q of perguntas) {
      const v = resp?.[q.id]?.bool;
      if (typeof v !== "number") {
        falhas.push(`${chave}: no answer for ${q.id}`);
        continue;
      }
      const classe = classificar(v, q.ruim_se, faixa);
      if (classe !== "limpo") achados.push({ onde: chave, pergunta: q.id, valor: Number(v.toFixed(2)), classe });
    }
  };
  for (const k of Object.keys(states)) ler(k, porCrit.ok[k], gi.perguntas);
  ler("global", global.ok.g, gi.perguntas_globais);
  return { falhas, achados, custo: porCrit.custo };
}

function feedbackDe(issue, achados, verificacao, motivos) {
  const l = [];
  for (const m of motivos) l.push(`- ${m}`);
  for (const a of achados) {
    const n = /^c(\d+)$/.exec(a.onde)?.[1];
    const quem = n ? `Criterion ${n} ("${issue.criterios[Number(n) - 1]}")` : "Report";
    l.push(`- ${quem}: ${MOTIVO[a.pergunta] ?? a.pergunta} (${a.classe}).`);
  }
  for (const v of verificacao) if (v.estado === "executado" && v.codigo !== 0) l.push(`- \`${v.comando}\` exited with code ${v.codigo}. End of the output:\n\`\`\`\n${v.saida}\n\`\`\``);
  return l.join("\n");
}

/** One iteration of one issue. `kernel`: { judge, judgeBatch, agent }. */
export async function passo(kernel, { sprint, issues, reabrir = [] }) {
  const cfg = carregarConfig();
  const cfgI = cfg.conducao.implementacao;
  const p = await plano({ sprint, issues, reabrir });
  if (p.bloqueios.length) return { acao: "bloqueado", motivos: p.bloqueios };
  if (!p.go) return { acao: "sem_go", proposta: p.proposta };
  const issue = p.proxima;
  if (!issue) {
    const pend = p.issues.filter(i => i.estado !== "ok" && i.estado !== "fechada");
    return { acao: "fim", ok: p.issues.filter(i => i.estado === "ok").map(i => i.numero), pendentes: pend.map(i => ({ numero: i.numero, estado: i.estado, motivo: i.bloqueio ?? i.ultima?.motivos?.join("; ") ?? null })) };
  }
  if (issue.dono.length === 0) return { acao: "bloqueado", motivos: [`#${issue.numero} with no owner in the recorded go`] };
  const max = p.go.max_iteracoes ?? cfgI.max_iteracoes;
  const iteracao = issue.iteracoes + 1;
  if (issue.estado === "reaberta") {
    if (iteracao > max) return { acao: "bloqueado", motivos: [`#${issue.numero} reopened beyond the limit of ${max} iteration(s)`] };
    anexar(sprint, { tipo: "implementacao_reabertura", issue: issue.numero, do_recibo: issue.reaberta?.recibo ?? null, origem: issue.origem, ato_do_dono: true });
  }
  const feedback =
    issue.ultima?.veredito === "reiterar"
      ? issue.ultima.feedback
      : issue.reaberta
        ? [
            `Block of iteration ${issue.reaberta.iteracao}, reopened by the owner. Reasons:`,
            ...(issue.reaberta.motivos ?? []).map(m => `- ${m}`),
            "- If some criterion of the issue was proven only with an ad-hoc command, add the permanent test that covers it to the suite.",
          ].join("\n")
        : null;

  grafo.atualizar();
  const pista = grafo.consultar(issue.titulo, { sementes: [...issue.caminhos, ...issue.dono] });
  const antes = instantaneo(cfgI);
  let relatorio = null;
  let erroAgente = null;
  try {
    const h = await kernel.agent(briefing(p, issue, feedback, cfgI, pista), {
      agent: issue.papel,
      label: camel(`Issue ${issue.numero} it${iteracao}`),
      schema: RELATORIO,
    });
    relatorio = await h.wait();
    if (!relatorio || typeof relatorio !== "object") erroAgente = "subagent did not return a structured report";
  } catch (e) {
    erroAgente = `subagent failed: ${String(e?.message ?? e)}`;
  }
  const depois = instantaneo(cfgI);
  const alterados = diferenca(antes, depois);
  const atualizado = grafo.atualizar();
  const impacto = alterados.length ? grafo.impacto(alterados) : [];

  const motivos = [];
  let bloqueada = false;
  if (erroAgente) {
    motivos.push(erroAgente);
    bloqueada = true;
  }
  if (antes.head !== depois.head) {
    motivos.push("the subagent changed git's HEAD (commit); committing is the owner's act");
    bloqueada = true;
  }
  const fora = alterados.filter(c => !dentro(c, issue.dono));
  if (fora.length) {
    motivos.push(`wrote outside the declared owner: ${fora.join(", ")}`);
    bloqueada = true;
  }
  const prot = alterados.filter(c => dentro(c, cfgI.protegidos));
  if (prot.length) {
    motivos.push(`touched a protected path: ${prot.join(", ")}`);
    bloqueada = true;
  }
  if (relatorio?.bloqueios?.length) {
    motivos.push(...relatorio.bloqueios.map(b => `subagente bloqueou: ${b}`));
    bloqueada = true;
  }

  const verificacao = bloqueada ? [] : verificar(cfgI);
  for (const v of verificacao) if (v.estado === "sem_verificador") {
    motivos.push(`no verifier for \`${v.comando}\`: ${v.motivo}`);
    bloqueada = true;
  }
  let julgamento = { falhas: [], achados: [], custo: null };
  const reiterar = [];
  if (!bloqueada) {
    if (alterados.length === 0 && iteracao === 1) reiterar.push("no file was changed");
    for (const v of verificacao) if (v.estado === "executado" && v.codigo !== 0) reiterar.push(`\`${v.comando}\` failed (code ${v.codigo})`);
    const anteriores = registros(sprint).filter(r => r.tipo === "implementacao_iteracao" && r.issue === issue.numero).flatMap(r => r.arquivos);
    julgamento = await avaliar(kernel, cfg, issue, relatorio, verificacao, [...new Set([...anteriores, ...alterados])].sort());
    if (julgamento.falhas.length) {
      motivos.push(...julgamento.falhas);
      bloqueada = true;
    }
  }
  let veredito;
  if (bloqueada) veredito = "bloqueada";
  else if (reiterar.length || julgamento.achados.length) veredito = iteracao >= max ? "bloqueada" : "reiterar";
  else veredito = "ok";
  if (veredito === "bloqueada" && !motivos.length) {
    motivos.push(`esgotou ${max} iteration(s) without covering all criteria`);
    motivos.push(...reiterar, ...julgamento.achados.map(a => `${a.onde}: ${a.pergunta}=${a.valor} (${a.classe})`));
  }
  const feedbackProx = veredito === "reiterar" ? feedbackDe(issue, julgamento.achados, verificacao, reiterar) : null;
  const recibo = sha(JSON.stringify({ sprint, issue: issue.numero, iteracao, relatorio, verificacao, alterados, modelo: cfg.modelo })).slice(0, 16);
  anexar(sprint, {
    tipo: "implementacao_iteracao",
    issue: issue.numero,
    iteracao,
    papel: issue.papel,
    veredito,
    motivos,
    achados: julgamento.achados,
    arquivos: alterados,
    impacto,
    grafo: grafo.resumo(atualizado.estado),
    testes: verificacao.map(v => ({ comando: v.comando, estado: v.estado, codigo: v.codigo ?? null, saida: v.saida ? cortar(v.saida, 1500, [], "saida") : null })),
    relatorio,
    feedback: feedbackProx,
    modelo: cfg.modelo,
    calibrado: cfg.calibrado,
    recibo,
  });
  return { acao: "iteracao", issue: issue.numero, titulo: issue.titulo, iteracao, max, veredito, motivos, achados: julgamento.achados, arquivos: alterados, impacto, testes: verificacao.map(v => `${v.comando}: ${v.estado === "executado" ? `code ${v.codigo}` : v.estado}`), recibo };
}

/** Summary line of the verifier output (e.g. `1 test, 0 failures`), or the last non-empty line. */
function resumoSaida(saida) {
  const linhas = (saida ?? "").split("\n").map(s => s.trim()).filter(Boolean);
  const alvo = [...linhas].reverse().find(s => /\d+ (tests?|doctests?).*failure/i.test(s)) ?? linhas.at(-1);
  return alvo ? ` — \`${alvo.slice(0, 120)}\`` : "";
}

function renderizar(p, regs, cfg) {
  const l = [
    "---",
    `sprint: ${p.sprint}`,
    "step: 05_implement",
    "---",
    "",
    MARCA,
    "",
    `# Implementation — ${p.sprint}`,
    "",
    "Record per iteration in [`jev.jsonl`](jev.jsonl). The verification column is what the orchestrator ran and measured; the text of each criterion below is what the subagent declared, and Jev judged it as advisory (`calibrado: " + cfg.calibrado + "`). No commit was made; no issue was closed. The owner checks the evidence.",
    "",
  ];
  for (const i of p.issues) {
    const ult = i.ultima;
    l.push(`## #${i.numero} — ${i.titulo}`, "", `- status: **${i.estado}** in ${i.iteracoes} iteration(s); role: \`${i.papel}\`; owner: ${i.dono.map(d => `\`${d}\``).join(", ") || "—"}`);
    if (!ult) {
      l.push(`- no iteration recorded${i.bloqueio ? `: ${i.bloqueio}` : ""}`, "");
      continue;
    }
    const acumulados = [...new Set(regs.filter(r => r.tipo === "implementacao_iteracao" && r.issue === i.numero).flatMap(r => r.arquivos))].sort();
    l.push(`- files changed across iterations (measured by hash before and after): ${acumulados.map(a => `\`${a}\``).join(", ") || "none"}`);
    const alcance = [...new Set(regs.filter(r => r.tipo === "implementacao_iteracao" && r.issue === i.numero).flatMap(r => (r.impacto ?? []).map(x => `${x.no} (${x.onde})`)))];
    if (alcance.length) l.push(`- reach, from the graphify graph (derived and approximate; a hint for the reviewer, not proof): ${alcance.map(a => `\`${a}\``).join(", ")}`);
    for (const t of ult.testes) l.push(`- verification: \`${t.comando}\` → ${t.estado === "executado" ? `code ${t.codigo}${resumoSaida(t.saida)}` : t.estado}`);
    for (const m of ult.motivos) l.push(`- ${ult.veredito === "ok" ? "note" : "pending"}: ${m}`);
    const crits = ult.relatorio?.criterios ?? [];
    if (crits.length) l.push("", "Criteria (declared by the subagent):");
    for (const c of crits) l.push(`- [${c.evidencia === "execucao" ? "x" : " "}] ${c.criterio} — ${c.atendimento} (evidence: ${c.evidencia}${c.comando ? `; \`${c.comando}\`` : ""})`);
    l.push(`- receipt: \`${ult.recibo}\``, "");
  }
  return l.join("\n");
}

/** When there is no issue left to run: writes `implementacao.md` (derived from the records) and runs the gate. */
export async function fechar(kernel, { sprint, issues }) {
  const cfg = carregarConfig();
  const p = await plano({ sprint, issues });
  if (p.bloqueios.length) return { acao: "bloqueado", motivos: p.bloqueios };
  if (p.proxima) return { acao: "bloqueado", motivos: [`there is still an issue to run: #${p.proxima.numero}`] };
  const rel = rel05(sprint, "implementacao.md");
  const existente = lerRel(rel);
  if (existente !== null && !existente.includes(MARCA)) return { acao: "bloqueado", motivos: [`${rel} exists and was not generated by this loop; I will not overwrite`] };
  writeFileSync(join(RAIZ, rel), renderizar(p, registros(sprint), cfg));
  const itens = p.issues.filter(i => i.estado === "ok").flatMap(i => i.criterios.map((c, k) => ({ id: `#${i.numero}.${k + 1}`, texto: c })));
  if (itens.length === 0) return { acao: "fechado", arquivo: rel, gate: "gate skipped: no ok issue to judge", veredito: "bloqueado", recibo: null };
  const r = await rodar(kernel, "implementacao", { sprint, itens });
  if (!r.falhas.length) registrar(r, { etapa: "05_implement" });
  return { acao: "fechado", arquivo: rel, gate: textoGate(r), veredito: r.veredito, recibo: r.recibo };
}

/** Short plan text. */
export function painel(p) {
  const l = [`implementation · ${p.sprint} · max. ${p.max_iteracoes} iteration(s) per issue · go: ${p.go ? p.go.em : "not recorded"}`];
  for (const b of p.bloqueios) l.push(`BLOCKED  ${b}`);
  for (const i of p.issues) {
    l.push(`  #${i.numero} [${i.estado}${i.iteracoes ? ` it${i.iteracoes}` : ""}${i.reaberta ? ", reopened by the owner" : ""}] ${i.titulo.slice(0, 60)} · ${i.criterios.length} criterion(s) · deps: ${i.deps.map(d => `#${d}`).join(",") || "—"} · role ${i.papel} · owner: ${i.dono.join(", ") || "—"}${i.bloqueio ? `\n      BLOCKED ${i.bloqueio}` : ""}`);
  }
  if (p.proxima) l.push(`next: #${p.proxima.numero}`);
  return l.join("\n");
}
