// Judgement gates of the EnochDB ICM. See docs/agents/jev.md.
//
// Runs inside the `eval` (omp's JS kernel), which provides `judge` and `judgeBatch`
// through the `judge` role of .omp/config.yml. The module does not import those globals:
// it receives them in `kernel`, which is also why it runs under test with a fake judge.
//
//   const g = await import("/abs/EnochDB/docs/_index/jev-gate.mjs");
//   const r = await g.rodar({ judge, judgeBatch }, "estado", { sprint: "s01-nucleo-enoch" });
//   console.log(g.texto(r));
//
// Rules the code guarantees (docs/agents/jev.md): the Jev only answers an atomic
// yes/no; existence, count and order are code; a tool, artefact or extraction
// failure is `bloqueado`, never a favourable verdict; no verdict writes status,
// closes a stage or generates artefact text.
import { createHash } from "node:crypto";
import { appendFileSync, existsSync, readFileSync, readdirSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

export const RAIZ = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");
export const ETAPAS = ["01_grilling", "02_domain", "03_spec", "04_tickets", "05_implement", "06_review", "07_handoff"];
const CHECKBOX = "^\\s*[-*]\\s+\\[[ xX]\\]\\s+(.*)$";
const ESPERA_MAX_MS = 10 * 60 * 1000;

export const sha = s => createHash("sha256").update(s).digest("hex");
export const lerRel = rel => (existsSync(join(RAIZ, rel)) ? readFileSync(join(RAIZ, rel), "utf8") : null);
export const caminho = (tpl, sprint) => tpl.replaceAll("{sprint}", sprint);

export function carregarConfig() {
  return JSON.parse(readFileSync(join(RAIZ, "docs/agents/jev-gates.json"), "utf8"));
}

/** Value of `chave:` in the frontmatter; `null` if absent. */
export function campo(texto, chave) {
  const m = /^---\n([\s\S]*?)\n---/.exec(texto ?? "");
  if (!m) return null;
  for (const linha of m[1].split("\n")) {
    if (linha.startsWith(`${chave}:`)) return linha.slice(chave.length + 1).replace(/\s+#.*$/, "").trim();
  }
  return null;
}

export function cortar(texto, max, trunc, rotulo) {
  if (texto.length <= max) return texto;
  trunc.push({ onde: rotulo, de: texto.length, para: max });
  return `${texto.slice(0, max)}\n…[truncated: ${texto.length - max} characters]`;
}

/** `ruim_se` + value + range → "achado" | "incerto" | "limpo". */
export function classificar(valor, ruimSe, [baixo, alto]) {
  if (valor > baixo && valor < alto) return "incerto";
  const ruim = ruimSe === "alto" ? valor >= alto : valor <= baixo;
  return ruim ? "achado" : "limpo";
}

export async function lote(kernel, states, questions, intent) {
  const ok = {};
  const erro = {};
  let custo = null;
  try {
    const batch = await kernel.judgeBatch(states, questions, { intent });
    const inicio = Date.now();
    while (Object.keys(ok).length + Object.keys(erro).length < batch.total) {
      if (Date.now() - inicio > ESPERA_MAX_MS) throw new Error("timed out waiting for the judge");
      for (const [k, item] of await batch.drain({ timeout: 30 })) {
        if (item.error !== undefined) erro[k] = String(item.error?.message ?? item.error);
        else ok[k] = item.answers;
      }
    }
    try {
      custo = (await batch.status()).cost ?? null;
    } catch {}
  } catch (e) {
    for (const k of Object.keys(states)) if (!(k in ok) && !(k in erro)) erro[k] = String(e?.message ?? e);
  }
  return { ok, erro, custo };
}

export const perguntasBool = lista =>
  Object.fromEntries(lista.map(p => [p.id, { type: "bool", instructions: p.instrucoes }]));

function avaliar(chaveItem, respostas, perguntas, faixa, saida) {
  for (const p of perguntas) {
    const valor = respostas?.[p.id]?.bool;
    if (typeof valor !== "number") {
      saida.falhas.push(`${chaveItem}: no answer for ${p.id}`);
      continue;
    }
    const classe = classificar(valor, p.ruim_se, faixa);
    if (classe !== "limpo") saida.achados.push({ item: chaveItem, pergunta: p.id, valor, ruim_se: p.ruim_se, classe });
  }
}

export function extrairItens(fonteRel, spec, trunc, max) {
  const texto = lerRel(fonteRel);
  if (texto === null) return { falha: `missing items source: ${fonteRel}` };
  const re = new RegExp(spec.padrao ?? CHECKBOX);
  const linhas = texto.split("\n");
  const marcas = [];
  linhas.forEach((l, i) => {
    const m = re.exec(l);
    if (m) marcas.push({ i, id: m.length > 1 && spec.padrao ? m[1] : null, linha: l });
  });
  const ate = spec.bloco === "linha" || !spec.padrao;
  const itens = marcas.map((m, n) => {
    let fim = m.i + 1;
    if (!ate) {
      const limite = marcas[n + 1]?.i ?? linhas.length;
      while (fim < limite && !linhas[fim].startsWith("#")) fim++;
    }
    const bruto = linhas.slice(m.i, fim).join("\n").trim();
    const id = m.id ?? `#${n + 1}`;
    return { id, texto: cortar(bruto, max, trunc, `item ${id}`) };
  });
  if (itens.length === 0) return { falha: `no item extracted from ${fonteRel} with the pattern ${spec.padrao ?? CHECKBOX}` };
  return { itens };
}

function resumoGit() {
  const git = (...a) => execFileSync("git", ["-C", RAIZ, ...a], { encoding: "utf8" }).trim();
  try {
    return {
      head: git("log", "-1", "--format=%h %s"),
      alteracoes: git("status", "--short").split("\n").filter(Boolean).length,
    };
  } catch (e) {
    return { erro: String(e.message ?? e) };
  }
}

/** Facts of the sprint state, all in code. */
export function fatosDoSprint(sprint) {
  const base = `docs/_sprints/${sprint}`;
  const falhas = [];
  const etapas = ETAPAS.map(nome => {
    const ficha = lerRel(`${base}/${nome}/CONTEXT.md`);
    const dir = join(RAIZ, base, nome, "handovers");
    const arquivos = existsSync(dir) ? readdirSync(dir).filter(f => f !== ".gitkeep") : [];
    return {
      nome,
      ficha,
      status: ficha === null ? null : campo(ficha, "status"),
      handovers: arquivos.filter(f => f !== ".closed" && f !== "jev.jsonl"),
      fechadaMarcador: arquivos.includes(".closed"),
    };
  });
  const fim = s => s === "fechado" || s === "nao-aplicavel";
  etapas.forEach((e, i) => {
    if (e.ficha === null) return falhas.push(`${e.nome}: missing sheet`);
    if (!["vazio", "em-curso", "fechado", "nao-aplicavel"].includes(e.status))
      falhas.push(`${e.nome}: invalid status (${e.status})`);
    if (e.status === "fechado" && e.handovers.length === 0 && !e.fechadaMarcador)
      falhas.push(`${e.nome}: closed without a handover or .closed`);
    if (e.status === "vazio" && e.handovers.length > 0) falhas.push(`${e.nome}: empty, but with handovers`);
    if (e.status === "fechado") {
      const anterior = etapas.slice(0, i).find(x => !fim(x.status));
      if (anterior) falhas.push(`${e.nome}: closed with ${anterior.nome} still ${anterior.status}`);
    }
  });
  return { etapas, falhas, git: resumoGit(), mix_exs: existsSync(join(RAIZ, "mix.exs")) };
}

function novoRelatorio(gate, sprint, cfg) {
  return {
    gate,
    sprint,
    modelo_configurado: cfg.modelo,
    calibrado: cfg.calibrado,
    faixa_incerta: cfg.faixa_incerta,
    achados: [],
    falhas: [],
    truncamentos: [],
    artefatos: {},
    custo: null,
  };
}

function finalizar(r, cfg, perguntas, extra = {}) {
  Object.assign(r, extra);
  r.veredito = r.falhas.length ? "bloqueado" : r.achados.length ? "revisar" : "sem_achados";
  r.recibo = sha(JSON.stringify({ gate: r.gate, sprint: r.sprint, artefatos: r.artefatos, perguntas, modelo: cfg.modelo, opcoes: extra.opcoes_hash ?? null })).slice(0, 16);
  return r;
}

async function gateEstado(kernel, g, sprint, cfg, r) {
  const fatos = fatosDoSprint(sprint);
  r.falhas.push(...fatos.falhas);
  r.fatos = { git: fatos.git, mix_exs: fatos.mix_exs, etapas: fatos.etapas.map(e => ({ nome: e.nome, status: e.status, handovers: e.handovers })) };
  const states = {};
  for (const e of fatos.etapas) {
    if (e.status !== "fechado" && e.status !== "em-curso") continue;
    if (e.handovers.length === 0) continue;
    const handovers = {};
    for (const h of e.handovers) {
      const rel = `docs/_sprints/${sprint}/${e.nome}/handovers/${h}`;
      const t = lerRel(rel);
      if (t === null) continue;
      r.artefatos[rel] = sha(t);
      handovers[h] = cortar(t, cfg.limite_estado_chars, r.truncamentos, rel);
    }
    r.artefatos[`docs/_sprints/${sprint}/${e.nome}/CONTEXT.md`] = sha(e.ficha);
    states[e.nome] = { etapa: e.nome, ficha: e.ficha, handovers };
  }
  const { ok, erro } = await lote(kernel, states, perguntasBool(g.perguntas), `estado ${sprint}`);
  for (const [k, msg] of Object.entries(erro)) r.falhas.push(`${k}: judge failed: ${msg}`);
  for (const [k, resp] of Object.entries(ok)) avaliar(k, resp, g.perguntas, cfg.faixa_incerta, r);
  r.julgados = Object.keys(states);
  return g.perguntas;
}

/** Files the source artefact of a gate cites (`artefatos_citados`), such as the ADRs linked by adrs.md. */
function citados(g, sprint) {
  const c = g.artefatos_citados;
  if (!c) return { arquivos: [], falhas: [] };
  const fonte = lerRel(caminho(g.artefatos[c.fonte], sprint));
  if (fonte === null) return { arquivos: [], falhas: [] };
  const nomes = [...new Set([...fonte.matchAll(new RegExp(c.padrao, "g"))].map(m => m[1]))].sort();
  const arquivos = nomes.map(n => `${c.base}${n}`);
  return { arquivos, falhas: arquivos.filter(a => lerRel(a) === null).map(a => `missing cited file: ${a}`) };
}

/**
 * All files the `evidencia` or `cobertura` gate reads, with the current hash. `aplicavel: false`
 * for the other types. Single source of what enters the receipt and of what freshness compares.
 */
export function artefatosDoGate(g, sprint) {
  if (g.tipo !== "evidencia" && g.tipo !== "cobertura") return { aplicavel: false, mapa: {}, falhas: [] };
  const rels = g.tipo === "evidencia" ? Object.values(g.artefatos).map(t => caminho(t, sprint)) : [caminho(g.artefatos.alvo, sprint)];
  if (g.tipo === "cobertura" && g.itens?.fonte) rels.push(caminho(g.itens.fonte, sprint));
  const ci = citados(g, sprint);
  const mapa = {};
  const falhas = [...ci.falhas];
  for (const rel of [...rels, ...ci.arquivos]) {
    const t = lerRel(rel);
    if (t === null) falhas.push(`missing artefact: ${rel}`);
    else mapa[rel] = sha(t);
  }
  return { aplicavel: true, mapa, falhas };
}

async function gateEvidencia(kernel, g, sprint, cfg, r) {
  const state = {};
  for (const [nome, tpl] of Object.entries(g.artefatos)) {
    const rel = caminho(tpl, sprint);
    const t = lerRel(rel);
    if (t === null) {
      r.falhas.push(`missing artefact: ${rel}`);
      continue;
    }
    r.artefatos[rel] = sha(t);
    state[nome] = cortar(t, cfg.limite_estado_chars, r.truncamentos, rel);
  }
  const ci = citados(g, sprint);
  r.falhas.push(...ci.falhas);
  for (const rel of ci.arquivos) {
    const t = lerRel(rel);
    if (t === null) continue;
    r.artefatos[rel] = sha(t);
    state[rel] = cortar(t, cfg.limite_estado_chars, r.truncamentos, rel);
  }
  if (r.falhas.length) return g.perguntas;
  const { ok, erro } = await lote(kernel, { artefatos: state }, perguntasBool(g.perguntas), `${g.etapa} ${sprint}`);
  for (const [k, msg] of Object.entries(erro)) r.falhas.push(`judge failed: ${msg}`);
  if (ok.artefatos) avaliar("artefatos", ok.artefatos, g.perguntas, cfg.faixa_incerta, r);
  return g.perguntas;
}

async function gateCobertura(kernel, g, sprint, cfg, r, args) {
  const alvoRel = caminho(g.artefatos.alvo, sprint);
  const alvo = lerRel(alvoRel);
  if (alvo === null) {
    r.falhas.push(`missing artefact: ${alvoRel}`);
    return g.perguntas;
  }
  r.artefatos[alvoRel] = sha(alvo);
  const alvoTxt = cortar(alvo, cfg.limite_estado_chars, r.truncamentos, alvoRel);
  if (g.itens?.fonte) {
    const fonteRel = caminho(g.itens.fonte, sprint);
    const fonteTxt = lerRel(fonteRel);
    if (fonteTxt !== null) r.artefatos[fonteRel] = sha(fonteTxt);
  }

  let itens = args.itens;
  if (!itens) {
    if (!g.itens?.fonte) {
      r.falhas.push("no items: pass `itens` or declare `itens.fonte` in the gate");
      return g.perguntas;
    }
    const fonteRel = caminho(g.itens.fonte, sprint);
    const ex = extrairItens(fonteRel, g.itens, r.truncamentos, cfg.limite_item_chars);
    if (ex.falha) {
      r.falhas.push(ex.falha);
      return g.perguntas;
    }
    r.artefatos[fonteRel] = sha(lerRel(fonteRel));
    itens = ex.itens;
  }
  if (itens.length === 0) {
    r.falhas.push("empty items list");
    return g.perguntas;
  }
  r.itens = itens.map(i => i.id);

  if (g.itens?.exigir_citacao) {
    for (const it of itens) {
      if (!new RegExp(`\\b${it.id.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\b`).test(alvo))
        r.achados.push({ item: it.id, pergunta: "without_citation", valor: 0, ruim_se: "codigo", classe: "achado" });
    }
  }

  const states = Object.fromEntries(itens.map(it => [it.id, { item: it, alvo: alvoTxt }]));
  const { ok, erro, custo } = await lote(kernel, states, perguntasBool(g.perguntas), `${g.etapa} cobertura ${sprint}`);
  r.custo = custo;
  for (const [k, msg] of Object.entries(erro)) r.falhas.push(`${k}: judge failed: ${msg}`);
  for (const [k, resp] of Object.entries(ok)) avaliar(k, resp, g.perguntas, cfg.faixa_incerta, r);

  if (g.perguntas_globais?.length) {
    const res = await lote(kernel, { alvo: { alvo: alvoTxt } }, perguntasBool(g.perguntas_globais), `${g.etapa} global ${sprint}`);
    for (const [k, msg] of Object.entries(res.erro)) r.falhas.push(`global: judge failed: ${msg}`);
    if (res.ok.alvo) avaliar("global", res.ok.alvo, g.perguntas_globais, cfg.faixa_incerta, r);
  }
  return [...g.perguntas, ...(g.perguntas_globais ?? [])];
}

/**
 * Options: each option is judged against each criterion (atomic yes/no); the
 * weighted average and the ranking come out of code. Advisory: the owner decides.
 * args: { decisao, opcoes:[{id,descricao}], criterios:[{id,texto,peso?}], contexto?:[relative paths] }
 */
async function gateOpcoes(kernel, g, sprint, cfg, r, args) {
  const { decisao, opcoes, criterios, contexto = [] } = args;
  if (!decisao || !opcoes?.length || !criterios?.length) {
    r.falhas.push("opcoes requires non-empty `decisao`, `opcoes` and `criterios`");
    return [];
  }
  if (opcoes.length < 2) r.falhas.push("opcoes requires at least 2 options");
  const ctx = {};
  for (const rel of contexto) {
    const t = lerRel(rel);
    if (t === null) {
      r.falhas.push(`missing context: ${rel}`);
      continue;
    }
    r.artefatos[rel] = sha(t);
    ctx[rel] = cortar(t, cfg.limite_estado_chars, r.truncamentos, rel);
  }
  if (r.falhas.length) return [];

  const perguntas = criterios.map(c => ({ id: c.id, instrucoes: `Does the option meet the criterion: ${c.texto}` }));
  const states = Object.fromEntries(
    opcoes.map(o => [o.id, { decisao, opcao: o, ...(contexto.length ? { contexto: ctx } : {}) }]),
  );
  const { ok, erro, custo } = await lote(kernel, states, perguntasBool(perguntas), `opcoes ${decisao.slice(0, 40)}`);
  r.custo = custo;
  for (const [k, msg] of Object.entries(erro)) r.falhas.push(`${k}: judge failed: ${msg}`);

  const soma = criterios.reduce((s, c) => s + (c.peso ?? 1), 0);
  const [baixo, alto] = cfg.faixa_incerta;
  const tabela = opcoes
    .filter(o => ok[o.id])
    .map(o => {
      const porCriterio = Object.fromEntries(criterios.map(c => [c.id, ok[o.id]?.[c.id]?.bool ?? null]));
      if (Object.values(porCriterio).some(v => v === null)) r.falhas.push(`${o.id}: incomplete answer`);
      const pontos = criterios.reduce((s, c) => s + (c.peso ?? 1) * (porCriterio[c.id] ?? 0), 0) / soma;
      const incertos = criterios.filter(c => porCriterio[c.id] > baixo && porCriterio[c.id] < alto).map(c => c.id);
      return { opcao: o.id, pontos: Number(pontos.toFixed(3)), por_criterio: porCriterio, incertos };
    })
    .sort((a, b) => b.pontos - a.pontos);
  const empate = tabela.length > 1 && tabela[0].pontos - tabela[1].pontos < (g.empate ?? 0.1);
  if (empate) r.achados.push({ item: `${tabela[0].opcao} × ${tabela[1].opcao}`, pergunta: "tie", valor: tabela[0].pontos - tabela[1].pontos, ruim_se: "codigo", classe: "incerto" });
  for (const t of tabela) if (t.incertos.length) r.achados.push({ item: t.opcao, pergunta: `uncertain: ${t.incertos.join(",")}`, valor: 0, ruim_se: "codigo", classe: "incerto" });
  r.opcoes_ranking = tabela;
  return { perguntas, opcoes_hash: sha(JSON.stringify({ decisao, opcoes, criterios })) };
}

/**
 * Runs a gate. `args`: { sprint, itens?, decisao?, opcoes?, criterios?, contexto? }.
 * Never throws for a judge or artefact failure: returns `veredito: "bloqueado"`.
 */
export async function rodar(kernel, nome, args = {}) {
  const cfg = carregarConfig();
  const g = cfg.gates[nome];
  if (!g) throw new Error(`unknown gate: ${nome}. Available: ${Object.keys(cfg.gates).join(", ")}`);
  const sprint = args.sprint;
  if (!sprint && g.tipo !== "opcoes") throw new Error("`sprint` is required");
  const r = novoRelatorio(nome, sprint ?? null, cfg);
  let perguntas;
  let extra = {};
  if (g.tipo === "estado") perguntas = await gateEstado(kernel, g, sprint, cfg, r);
  else if (g.tipo === "evidencia") perguntas = await gateEvidencia(kernel, g, sprint, cfg, r);
  else if (g.tipo === "cobertura") perguntas = await gateCobertura(kernel, g, sprint, cfg, r, args);
  else {
    const res = await gateOpcoes(kernel, g, sprint, cfg, r, args);
    perguntas = res.perguntas ?? [];
    extra = { opcoes_hash: res.opcoes_hash };
  }
  r.etapa = g.etapa ?? null;
  return finalizar(r, cfg, perguntas, extra);
}

/** Short text for the human. Does not replace the human gate. */
export function texto(r) {
  const l = [`gate ${r.gate}${r.sprint ? ` · ${r.sprint}` : ""} · veredito: ${r.veredito} (advisory; does not close a stage)`];
  l.push(`model: ${r.modelo_configurado} · calibrated: ${r.calibrado} · receipt: ${r.recibo}${r.custo != null ? ` · cost: ${r.custo}` : ""}`);
  if (r.itens) l.push(`items evaluated: ${r.itens.length}`);
  if (r.julgados) l.push(`stages judged: ${r.julgados.join(", ") || "none"}`);
  for (const f of r.falhas) l.push(`BLOCKED  ${f}`);
  for (const a of r.achados) {
    const rotulo = a.classe === "achado" ? "FINDING  " : "UNCERTAIN";
    const medida = a.ruim_se === "codigo" ? "(verification in code)" : `= ${a.valor.toFixed(2)} (bad if ${a.ruim_se})`;
    l.push(`${rotulo} ${a.item} · ${a.pergunta} ${medida}`);
  }
  if (r.opcoes_ranking) for (const t of r.opcoes_ranking) l.push(`option ${t.opcao}: ${t.pontos}`);
  for (const t of r.truncamentos) l.push(`TRUNCATED  ${t.onde}: ${t.de} → ${t.para}`);
  return l.join("\n");
}

const caminhoJsonl = (sprint, etapa) => `docs/_sprints/${sprint}/${etapa}/handovers/jev.jsonl`;

/** Appends the receipt to the stage handover; idempotent by `recibo`. Only `evidencia`/`cobertura`/`estado` with a known stage. */
export function registrar(r, { etapa = r.etapa } = {}) {
  if (!etapa) throw new Error("gate without a stage: pass { etapa }");
  const rel = caminhoJsonl(r.sprint, etapa);
  const atual = lerRel(rel) ?? "";
  if (atual.split("\n").some(l => l && JSON.parse(l).recibo === r.recibo && JSON.parse(l).tipo === "veredito")) return { rel, gravado: false };
  const linha = { tipo: "veredito", em: new Date().toISOString(), ...r };
  appendFileSync(join(RAIZ, rel), `${JSON.stringify(linha)}\n`);
  return { rel, gravado: true };
}

/** Records the owner's decision for a receipt. Only after the owner declares it. */
export function registrarDecisao({ sprint, etapa, recibo, decisao }) {
  if (!["aceito", "rejeitado", "ajustado"].includes(decisao)) throw new Error("decisao ∈ aceito|rejeitado|ajustado");
  const rel = caminhoJsonl(sprint, etapa);
  const existe = (lerRel(rel) ?? "").split("\n").some(l => l && JSON.parse(l).recibo === recibo && JSON.parse(l).tipo === "veredito");
  if (!existe) throw new Error(`receipt ${recibo} is not in ${rel}`);
  appendFileSync(join(RAIZ, rel), `${JSON.stringify({ tipo: "decisao_humana", em: new Date().toISOString(), recibo, decisao })}\n`);
  return { rel };
}

/**
 * Freshness of a stage's gate, derived (A4): compares the current hash of the artefacts the gate reads with
 * that of the last recorded receipt. Does not call the Jev. `estado`: `sem_gate` | `sem_artefato` | `sem_recibo` |
 * `desatualizado` | `atual`. A blocked receipt is never recorded, so it does not count as a receipt.
 */
export function frescor(sprint, etapa) {
  const cfg = carregarConfig();
  const nome = cfg.conducao.gate_por_etapa[etapa];
  const g = nome ? cfg.gates[nome] : null;
  if (!g) return { estado: "sem_gate", etapa };
  const { aplicavel, mapa, falhas } = artefatosDoGate(g, sprint);
  if (!aplicavel) return { estado: "sem_gate", etapa, gate: nome };
  if (falhas.length) return { estado: "sem_artefato", etapa, gate: nome, falhas };
  const vereditos = (lerRel(caminhoJsonl(sprint, etapa)) ?? "")
    .split("\n")
    .filter(Boolean)
    .map(l => JSON.parse(l))
    .filter(x => x.tipo === "veredito" && x.gate === nome);
  const ultimo = vereditos.at(-1);
  if (!ultimo) return { estado: "sem_recibo", etapa, gate: nome };
  const mudados = Object.entries(mapa).filter(([rel, h]) => ultimo.artefatos?.[rel] !== h).map(([rel]) => rel);
  return { estado: mudados.length ? "desatualizado" : "atual", etapa, gate: nome, recibo: ultimo.recibo, veredito: ultimo.veredito, mudados };
}
