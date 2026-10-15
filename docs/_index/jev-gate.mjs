// Gates de julgamento do ICM do EnochDB. Ver docs/agents/jev.md.
//
// Roda dentro do `eval` (kernel JS do omp), que fornece `judge` e `judgeBatch`
// pelo papel `judge` de .omp/config.yml. O módulo não importa esses globais:
// recebe-os em `kernel`, e por isso também roda sob teste com um judge falso.
//
//   const g = await import("/abs/EnochDB/docs/_index/jev-gate.mjs");
//   const r = await g.rodar({ judge, judgeBatch }, "estado", { sprint: "s01-nucleo-enoch" });
//   console.log(g.texto(r));
//
// Regras que o código garante (docs/agents/jev.md): o Jev só responde sim/não
// atômico; existência, contagem e ordem são código; falha de ferramenta, de
// artefato ou de extração é `bloqueado`, nunca um veredito favorável; nenhum
// veredito escreve status, fecha etapa ou gera texto de artefato.
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

/** Valor de `chave:` no frontmatter; `null` se não houver. */
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
  return `${texto.slice(0, max)}\n…[truncado: ${texto.length - max} caracteres]`;
}

/** `ruim_se` + valor + faixa → "achado" | "incerto" | "limpo". */
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
      if (Date.now() - inicio > ESPERA_MAX_MS) throw new Error("tempo esgotado esperando o judge");
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
      saida.falhas.push(`${chaveItem}: sem resposta para ${p.id}`);
      continue;
    }
    const classe = classificar(valor, p.ruim_se, faixa);
    if (classe !== "limpo") saida.achados.push({ item: chaveItem, pergunta: p.id, valor, ruim_se: p.ruim_se, classe });
  }
}

export function extrairItens(fonteRel, spec, trunc, max) {
  const texto = lerRel(fonteRel);
  if (texto === null) return { falha: `fonte de itens ausente: ${fonteRel}` };
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
  if (itens.length === 0) return { falha: `nenhum item extraído de ${fonteRel} com o padrão ${spec.padrao ?? CHECKBOX}` };
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

/** Fatos do estado do sprint, todos em código. */
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
    if (e.ficha === null) return falhas.push(`${e.nome}: ficha ausente`);
    if (!["vazio", "em-curso", "fechado", "nao-aplicavel"].includes(e.status))
      falhas.push(`${e.nome}: status inválido (${e.status})`);
    if (e.status === "fechado" && e.handovers.length === 0 && !e.fechadaMarcador)
      falhas.push(`${e.nome}: fechada sem handover nem .closed`);
    if (e.status === "vazio" && e.handovers.length > 0) falhas.push(`${e.nome}: vazia, mas com handovers`);
    if (e.status === "fechado") {
      const anterior = etapas.slice(0, i).find(x => !fim(x.status));
      if (anterior) falhas.push(`${e.nome}: fechada com ${anterior.nome} ainda ${anterior.status}`);
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
  for (const [k, msg] of Object.entries(erro)) r.falhas.push(`${k}: judge falhou: ${msg}`);
  for (const [k, resp] of Object.entries(ok)) avaliar(k, resp, g.perguntas, cfg.faixa_incerta, r);
  r.julgados = Object.keys(states);
  return g.perguntas;
}

/** Arquivos que o artefato-fonte de um gate cita (`artefatos_citados`), como os ADRs linkados pelo adrs.md. */
function citados(g, sprint) {
  const c = g.artefatos_citados;
  if (!c) return { arquivos: [], falhas: [] };
  const fonte = lerRel(caminho(g.artefatos[c.fonte], sprint));
  if (fonte === null) return { arquivos: [], falhas: [] };
  const nomes = [...new Set([...fonte.matchAll(new RegExp(c.padrao, "g"))].map(m => m[1]))].sort();
  const arquivos = nomes.map(n => `${c.base}${n}`);
  return { arquivos, falhas: arquivos.filter(a => lerRel(a) === null).map(a => `arquivo citado ausente: ${a}`) };
}

/**
 * Todos os arquivos que o gate de `evidencia` ou `cobertura` lê, com o hash atual. `aplicavel: false`
 * para os demais tipos. Fonte única do que entra no recibo e do que o frescor compara.
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
    if (t === null) falhas.push(`artefato ausente: ${rel}`);
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
      r.falhas.push(`artefato ausente: ${rel}`);
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
  for (const [k, msg] of Object.entries(erro)) r.falhas.push(`judge falhou: ${msg}`);
  if (ok.artefatos) avaliar("artefatos", ok.artefatos, g.perguntas, cfg.faixa_incerta, r);
  return g.perguntas;
}

async function gateCobertura(kernel, g, sprint, cfg, r, args) {
  const alvoRel = caminho(g.artefatos.alvo, sprint);
  const alvo = lerRel(alvoRel);
  if (alvo === null) {
    r.falhas.push(`artefato ausente: ${alvoRel}`);
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
      r.falhas.push("sem itens: passe `itens` ou declare `itens.fonte` no gate");
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
    r.falhas.push("lista de itens vazia");
    return g.perguntas;
  }
  r.itens = itens.map(i => i.id);

  if (g.itens?.exigir_citacao) {
    for (const it of itens) {
      if (!new RegExp(`\\b${it.id.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\b`).test(alvo))
        r.achados.push({ item: it.id, pergunta: "sem_citacao", valor: 0, ruim_se: "codigo", classe: "achado" });
    }
  }

  const states = Object.fromEntries(itens.map(it => [it.id, { item: it, alvo: alvoTxt }]));
  const { ok, erro, custo } = await lote(kernel, states, perguntasBool(g.perguntas), `${g.etapa} cobertura ${sprint}`);
  r.custo = custo;
  for (const [k, msg] of Object.entries(erro)) r.falhas.push(`${k}: judge falhou: ${msg}`);
  for (const [k, resp] of Object.entries(ok)) avaliar(k, resp, g.perguntas, cfg.faixa_incerta, r);

  if (g.perguntas_globais?.length) {
    const res = await lote(kernel, { alvo: { alvo: alvoTxt } }, perguntasBool(g.perguntas_globais), `${g.etapa} global ${sprint}`);
    for (const [k, msg] of Object.entries(res.erro)) r.falhas.push(`global: judge falhou: ${msg}`);
    if (res.ok.alvo) avaliar("global", res.ok.alvo, g.perguntas_globais, cfg.faixa_incerta, r);
  }
  return [...g.perguntas, ...(g.perguntas_globais ?? [])];
}

/**
 * Opções: cada opção é julgada contra cada critério (sim/não atômico); a
 * média ponderada e o ranking saem em código. Consultivo: quem decide é o dono.
 * args: { decisao, opcoes:[{id,descricao}], criterios:[{id,texto,peso?}], contexto?:[caminhos relativos] }
 */
async function gateOpcoes(kernel, g, sprint, cfg, r, args) {
  const { decisao, opcoes, criterios, contexto = [] } = args;
  if (!decisao || !opcoes?.length || !criterios?.length) {
    r.falhas.push("opcoes exige `decisao`, `opcoes` e `criterios` não vazios");
    return [];
  }
  if (opcoes.length < 2) r.falhas.push("opcoes exige ao menos 2 opções");
  const ctx = {};
  for (const rel of contexto) {
    const t = lerRel(rel);
    if (t === null) {
      r.falhas.push(`contexto ausente: ${rel}`);
      continue;
    }
    r.artefatos[rel] = sha(t);
    ctx[rel] = cortar(t, cfg.limite_estado_chars, r.truncamentos, rel);
  }
  if (r.falhas.length) return [];

  const perguntas = criterios.map(c => ({ id: c.id, instrucoes: `A opção atende ao critério: ${c.texto}` }));
  const states = Object.fromEntries(
    opcoes.map(o => [o.id, { decisao, opcao: o, ...(contexto.length ? { contexto: ctx } : {}) }]),
  );
  const { ok, erro, custo } = await lote(kernel, states, perguntasBool(perguntas), `opcoes ${decisao.slice(0, 40)}`);
  r.custo = custo;
  for (const [k, msg] of Object.entries(erro)) r.falhas.push(`${k}: judge falhou: ${msg}`);

  const soma = criterios.reduce((s, c) => s + (c.peso ?? 1), 0);
  const [baixo, alto] = cfg.faixa_incerta;
  const tabela = opcoes
    .filter(o => ok[o.id])
    .map(o => {
      const porCriterio = Object.fromEntries(criterios.map(c => [c.id, ok[o.id]?.[c.id]?.bool ?? null]));
      if (Object.values(porCriterio).some(v => v === null)) r.falhas.push(`${o.id}: resposta incompleta`);
      const pontos = criterios.reduce((s, c) => s + (c.peso ?? 1) * (porCriterio[c.id] ?? 0), 0) / soma;
      const incertos = criterios.filter(c => porCriterio[c.id] > baixo && porCriterio[c.id] < alto).map(c => c.id);
      return { opcao: o.id, pontos: Number(pontos.toFixed(3)), por_criterio: porCriterio, incertos };
    })
    .sort((a, b) => b.pontos - a.pontos);
  const empate = tabela.length > 1 && tabela[0].pontos - tabela[1].pontos < (g.empate ?? 0.1);
  if (empate) r.achados.push({ item: `${tabela[0].opcao} × ${tabela[1].opcao}`, pergunta: "empate", valor: tabela[0].pontos - tabela[1].pontos, ruim_se: "codigo", classe: "incerto" });
  for (const t of tabela) if (t.incertos.length) r.achados.push({ item: t.opcao, pergunta: `incertos: ${t.incertos.join(",")}`, valor: 0, ruim_se: "codigo", classe: "incerto" });
  r.opcoes_ranking = tabela;
  return { perguntas, opcoes_hash: sha(JSON.stringify({ decisao, opcoes, criterios })) };
}

/**
 * Roda um gate. `args`: { sprint, itens?, decisao?, opcoes?, criterios?, contexto? }.
 * Nunca lança por falha de judge ou de artefato: devolve `veredito: "bloqueado"`.
 */
export async function rodar(kernel, nome, args = {}) {
  const cfg = carregarConfig();
  const g = cfg.gates[nome];
  if (!g) throw new Error(`gate desconhecido: ${nome}. Disponíveis: ${Object.keys(cfg.gates).join(", ")}`);
  const sprint = args.sprint;
  if (!sprint && g.tipo !== "opcoes") throw new Error("`sprint` é obrigatório");
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

/** Texto curto para o humano. Não substitui o gate humano. */
export function texto(r) {
  const l = [`gate ${r.gate}${r.sprint ? ` · ${r.sprint}` : ""} · veredito: ${r.veredito} (consultivo; não fecha etapa)`];
  l.push(`modelo: ${r.modelo_configurado} · calibrado: ${r.calibrado} · recibo: ${r.recibo}${r.custo != null ? ` · custo: ${r.custo}` : ""}`);
  if (r.itens) l.push(`itens avaliados: ${r.itens.length}`);
  if (r.julgados) l.push(`etapas julgadas: ${r.julgados.join(", ") || "nenhuma"}`);
  for (const f of r.falhas) l.push(`BLOQUEIO  ${f}`);
  for (const a of r.achados) {
    const rotulo = a.classe === "achado" ? "ACHADO   " : "INCERTO  ";
    const medida = a.ruim_se === "codigo" ? "(verificação em código)" : `= ${a.valor.toFixed(2)} (ruim se ${a.ruim_se})`;
    l.push(`${rotulo} ${a.item} · ${a.pergunta} ${medida}`);
  }
  if (r.opcoes_ranking) for (const t of r.opcoes_ranking) l.push(`opção ${t.opcao}: ${t.pontos}`);
  for (const t of r.truncamentos) l.push(`TRUNCADO  ${t.onde}: ${t.de} → ${t.para}`);
  return l.join("\n");
}

const caminhoJsonl = (sprint, etapa) => `docs/_sprints/${sprint}/${etapa}/handovers/jev.jsonl`;

/** Acrescenta o recibo ao handover da etapa; idempotente pelo `recibo`. Só `evidencia`/`cobertura`/`estado` com etapa conhecida. */
export function registrar(r, { etapa = r.etapa } = {}) {
  if (!etapa) throw new Error("gate sem etapa: passe { etapa }");
  const rel = caminhoJsonl(r.sprint, etapa);
  const atual = lerRel(rel) ?? "";
  if (atual.split("\n").some(l => l && JSON.parse(l).recibo === r.recibo && JSON.parse(l).tipo === "veredito")) return { rel, gravado: false };
  const linha = { tipo: "veredito", em: new Date().toISOString(), ...r };
  appendFileSync(join(RAIZ, rel), `${JSON.stringify(linha)}\n`);
  return { rel, gravado: true };
}

/** Grava a decisão do dono para um recibo. Só depois de o dono declará-la. */
export function registrarDecisao({ sprint, etapa, recibo, decisao }) {
  if (!["aceito", "rejeitado", "ajustado"].includes(decisao)) throw new Error("decisao ∈ aceito|rejeitado|ajustado");
  const rel = caminhoJsonl(sprint, etapa);
  const existe = (lerRel(rel) ?? "").split("\n").some(l => l && JSON.parse(l).recibo === recibo && JSON.parse(l).tipo === "veredito");
  if (!existe) throw new Error(`recibo ${recibo} não está em ${rel}`);
  appendFileSync(join(RAIZ, rel), `${JSON.stringify({ tipo: "decisao_humana", em: new Date().toISOString(), recibo, decisao })}\n`);
  return { rel };
}

/**
 * Frescor do gate de uma etapa, derivado (A4): compara o hash atual dos artefatos que o gate lê com o
 * do último recibo gravado. Não chama o Jev. `estado`: `sem_gate` | `sem_artefato` | `sem_recibo` |
 * `desatualizado` | `atual`. Um recibo bloqueado nunca é gravado, então não conta como recibo.
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
