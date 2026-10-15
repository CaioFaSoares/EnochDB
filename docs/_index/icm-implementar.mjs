// Loop de implementação do ICM do EnochDB (`/icm implement`). Ver docs/agents/jev.md §Implementar.
//
// Uma chamada de `passo` executa UMA iteração de UMA issue: despacha o dono da
// fatia, mede o que ele realmente alterou, roda a verificação, pergunta ao Jev
// se cada critério de aceite foi coberto com execução observada e grava o
// resultado. O orquestrador chama `passo` até devolver `fim` ou `bloqueado`.
// O progresso é derivado de `05_implement/handovers/jev.jsonl` (A4): quem retoma
// a sessão continua de onde o arquivo parou.
//
//   const I = await import(`${process.cwd()}/docs/_index/icm-implementar.mjs`);
//   const p = await I.plano({ sprint });          // read-only: ordem, critérios, proposta de go
//   I.registrarGo({ sprint, itens: [...] });      // só depois do go do dono
//   const r = await I.passo({ judge, judgeBatch, agent }, { sprint });
//   const f = await I.fechar({ judge, judgeBatch }, { sprint });  // quando `fim`
//
// Quem decide é código: ordem, dono dos arquivos, escopo realmente escrito,
// resultado da verificação, limite de iterações e o veredito final. O Jev só dá
// a probabilidade de cada critério estar coberto por execução observada.
// Falha de judge, de verificador, de subagente ou de escopo é `bloqueada`,
// nunca `ok`. Nada aqui comita, fecha issue, muda `status:` nem edita o
// que está em `implementacao.protegidos`.
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
    bloqueios: { type: "array", items: { type: "string" } },
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

/** Estado derivado de cada issue da sprint a partir dos registros. */
function estadoDe(regs, numero) {
  const ultima = [...regs].reverse().find(r => r.tipo === "implementacao_iteracao" && r.issue === numero);
  if (!ultima) return { estado: "pendente", iteracoes: 0, ultima: null };
  const estado = ultima.veredito === "ok" ? "ok" : ultima.veredito === "bloqueada" ? "bloqueada" : "em-curso";
  return { estado, iteracoes: ultima.iteracao, ultima };
}

function carregarIssues(sprint, numerosArg) {
  let numeros = numerosArg;
  if (!numeros) {
    const t = lerRel(`docs/_sprints/${sprint}/04_tickets/handovers/tickets.md`);
    if (t === null) return { falha: "sem 04_tickets/handovers/tickets.md: a lista de issues da sprint são os `#N` citados nele (ou passe `issues`)" };
    numeros = [...new Set([...t.matchAll(/(?<![\w/])#(\d+)\b/g)].map(m => Number(m[1])))];
    if (numeros.length === 0) return { falha: "tickets.md não cita nenhuma issue como `#N`; registre o número de cada issue publicada" };
  }
  let todas;
  try {
    todas = JSON.parse(
      execFileSync("gh", ["issue", "list", "--state", "all", "--limit", "200", "--json", "number,title,body,state,url"], {
        cwd: RAIZ, encoding: "utf8", timeout: 30000,
      }),
    );
  } catch (e) {
    return { falha: `gh issue list falhou: ${String(e.stderr || e.message).trim().split("\n")[0]}` };
  }
  const porNumero = new Map(todas.map(i => [i.number, i]));
  const ausentes = numeros.filter(n => !porNumero.has(n));
  if (ausentes.length) return { falha: `issues inexistentes no tracker: ${ausentes.map(n => `#${n}`).join(", ")}` };
  return { numeros, porNumero };
}

/**
 * Plano read-only. Devolve a ordem (topológica por dependências declaradas),
 * os critérios extraídos em código, o estado derivado e uma proposta de go.
 */
export async function plano({ sprint, issues: numerosArg }) {
  const cfg = carregarConfig();
  const cfgI = cfg.conducao.implementacao;
  const p = { sprint, bloqueios: [], issues: [], proxima: null, go: null, max_iteracoes: cfgI.max_iteracoes };
  const fatos = fatosDoSprint(sprint);
  const atual = etapaAtual(fatos);
  if (fatos.falhas.length) p.bloqueios.push(...fatos.falhas);
  if (!atual || atual.nome !== "05_implement") {
    p.bloqueios.push(`a etapa atual é ${atual?.nome ?? "nenhuma"}; o loop só roda em 05_implement (04_tickets precisa estar fechada ou não aplicável)`);
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
      ...estadoDe(regs, n),
      ...(i.state === "CLOSED" && !regs.some(r => r.tipo === "implementacao_iteracao" && r.issue === n) ? { estado: "fechada" } : {}),
    };
  });
  // ordem topológica estável por número; ciclo e dependência externa aberta são bloqueios
  const porNum = new Map(itens.map(i => [i.numero, i]));
  const ordem = [];
  const visto = new Set();
  const pilha = new Set();
  const visitar = i => {
    if (visto.has(i.numero)) return;
    if (pilha.has(i.numero)) {
      p.bloqueios.push(`ciclo de dependências envolvendo #${i.numero}`);
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
      i.bloqueio = "issue sem critérios de aceite extraíveis (`- [ ]` na seção de critérios)";
    }
    const externas = i.deps.filter(d => !noSprint.has(d));
    for (const d of externas) {
      const s = carregadas.porNumero.get(d)?.state;
      if (s === undefined) i.bloqueio = `depende de #${d}, que não está na sprint nem foi consultada; passe-a em \`issues\` ou resolva`;
      else if (s === "OPEN") i.bloqueio = `depende de #${d}, aberta e fora da sprint`;
    }
  }
  const concluida = n => ["ok", "fechada"].includes(porNum.get(n)?.estado) || (!noSprint.has(n) && carregadas.porNumero.get(n)?.state === "CLOSED");
  for (const i of ordem) {
    if (["ok", "bloqueada", "fechada"].includes(i.estado)) continue;
    if (i.bloqueio) continue;
    const dep = i.deps.find(d => porNum.get(d)?.estado === "bloqueada" || porNum.get(d)?.bloqueio);
    if (dep) {
      i.bloqueio = `depende de #${dep}, que está ${porNum.get(dep).estado === "bloqueada" ? "bloqueada" : "bloqueada por dependência ou critério"}`;
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

/** Grava o go do dono: um papel e um dono de caminhos por issue. Só depois de o dono confirmar. */
export function registrarGo({ sprint, itens, max_iteracoes }) {
  const cfgI = carregarConfig().conducao.implementacao;
  if (!itens?.length) throw new Error("go sem itens");
  const vistos = new Set();
  for (const it of itens) {
    if (!Number.isInteger(it.numero) || vistos.has(it.numero)) throw new Error(`issue inválida ou repetida: ${it.numero}`);
    vistos.add(it.numero);
    if (!it.papel || !existsSync(join(RAIZ, ".omp", "agents", `${it.papel}.md`))) throw new Error(`#${it.numero}: papel inexistente no roster: ${it.papel}`);
    if (!it.dono?.length) throw new Error(`#${it.numero}: sem dono de arquivos; declare ao menos um caminho`);
    for (const c of it.dono) {
      if (!caminhoValido(c)) throw new Error(`#${it.numero}: caminho inválido: ${c}`);
      if (dentro(c, cfgI.protegidos) || cfgI.protegidos.some(p => p.startsWith(c))) throw new Error(`#${it.numero}: caminho protegido não pode ser dono: ${c}`);
    }
  }
  const max = max_iteracoes ?? cfgI.max_iteracoes;
  anexar(sprint, { tipo: "implementacao_go", itens, max_iteracoes: max });
  return { itens: itens.length, max_iteracoes: max };
}

function assinatura(abs) {
  if (!existsSync(abs) && !lstatSync(abs, { throwIfNoEntry: false })) return "removido";
  const s = lstatSync(abs);
  if (s.isSymbolicLink()) return `link:${readlinkSync(abs)}`;
  if (s.isDirectory()) return "diretorio";
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
      resultados.push({ comando: v.comando, estado: "sem_verificador", motivo: `${v.requer} não existe` });
      continue;
    }
    try {
      const saida = execFileSync("sh", ["-c", v.comando], {
        cwd: RAIZ, encoding: "utf8", timeout: cfgI.timeout_verificacao_s * 1000, maxBuffer: 64 * 1024 * 1024, stdio: ["ignore", "pipe", "pipe"],
      });
      resultados.push({ comando: v.comando, estado: "executado", codigo: 0, saida: saida.slice(-cfgI.limite_saida_chars) });
    } catch (e) {
      const saida = `${e.stdout ?? ""}${e.stderr ?? ""}`.slice(-cfgI.limite_saida_chars);
      if (e.status === 127 || e.code === "ENOENT") resultados.push({ comando: v.comando, estado: "sem_verificador", motivo: `comando indisponível: ${saida.trim().split("\n").pop() || e.message}` });
      else if (e.killed || e.signal) resultados.push({ comando: v.comando, estado: "sem_verificador", motivo: `tempo esgotado (${cfgI.timeout_verificacao_s}s)` });
      else resultados.push({ comando: v.comando, estado: "executado", codigo: e.status ?? 1, saida });
    }
  }
  return resultados;
}

function briefing(p, issue, feedback, cfgI) {
  const caminhos = issue.caminhos.length ? issue.caminhos.map(c => `\`${c}\``).join(", ") : "nenhum citado";
  const verifs = cfgI.verificacao.map(v => `\`${v.comando}\``).join(", ");
  const partes = [
    contextoCompartilhado(p.sprint, "05_implement"),
    "",
    "# Target",
    `Issue #${issue.numero}: ${issue.titulo}. Leia o corpo com \`gh issue view ${issue.numero}\` (cwd na raiz do repositório); ele não foi copiado aqui. A seção de critérios de aceite tem ${issue.criterios.length} item(ns).`,
    `Caminhos citados na issue (existem): ${caminhos}.`,
    `Você é o dono **somente** destes caminhos: ${issue.dono.map(d => `\`${d}\``).join(", ")}. Escrever fora deles, comitar ou editar \`${cfgI.protegidos.join("`, `")}\` invalida a iteração.`,
    "",
    "# Change",
    `Entregue só o que a issue #${issue.numero} pede. Teste primeiro quando houver seam. Não adicione dependência nem troque ferramenta; se faltar algo, devolva \`bloqueios\`. Não comite.`,
    `O orquestrador roda ${verifs} depois de você, mas rode o que o critério pedir e relate comando e resultado reais.`,
    "",
    "# Acceptance",
    `Devolva o relatório estruturado: \`arquivos\` tocados, \`criterios\` (um item por critério de aceite, na ordem da issue, com o texto do critério, como foi atendido e a evidência \`execucao\`, \`leitura\` ou \`nenhuma\`), \`comandos\` executados com o resultado observado e \`bloqueios\`.`,
  ];
  if (feedback) partes.push("", "# Iteração anterior falhou", feedback);
  return partes.join("\n");
}

const MOTIVO = {
  coberto_com_execucao: "sem execução registrada com resultado observado que cubra o critério",
  so_leitura: "o critério só tem leitura de código ou documento como prova",
  alega_sem_provar: "o relatório declara pronto sem comando e resultado",
  declara_execucao: "o relatório não registra nenhum comando executado com resultado",
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
    lote(kernel, states, perguntasBool(gi.perguntas), `implementacao #${issue.numero} critérios`),
    lote(kernel, { g: base }, perguntasBool(gi.perguntas_globais), `implementacao #${issue.numero} global`),
  ]);
  for (const [k, m] of [...Object.entries(porCrit.erro), ...Object.entries(global.erro)]) falhas.push(`judge falhou (${k}): ${m}`);
  const ler = (chave, resp, perguntas) => {
    for (const q of perguntas) {
      const v = resp?.[q.id]?.bool;
      if (typeof v !== "number") {
        falhas.push(`${chave}: sem resposta para ${q.id}`);
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
    const quem = n ? `Critério ${n} ("${issue.criterios[Number(n) - 1]}")` : "Relatório";
    l.push(`- ${quem}: ${MOTIVO[a.pergunta] ?? a.pergunta} (${a.classe}).`);
  }
  for (const v of verificacao) if (v.estado === "executado" && v.codigo !== 0) l.push(`- \`${v.comando}\` saiu com código ${v.codigo}. Final da saída:\n\`\`\`\n${v.saida}\n\`\`\``);
  return l.join("\n");
}

/** Uma iteração de uma issue. `kernel`: { judge, judgeBatch, agent }. */
export async function passo(kernel, { sprint, issues }) {
  const cfg = carregarConfig();
  const cfgI = cfg.conducao.implementacao;
  const p = await plano({ sprint, issues });
  if (p.bloqueios.length) return { acao: "bloqueado", motivos: p.bloqueios };
  if (!p.go) return { acao: "sem_go", proposta: p.proposta };
  const issue = p.proxima;
  if (!issue) {
    const pend = p.issues.filter(i => i.estado !== "ok" && i.estado !== "fechada");
    return { acao: "fim", ok: p.issues.filter(i => i.estado === "ok").map(i => i.numero), pendentes: pend.map(i => ({ numero: i.numero, estado: i.estado, motivo: i.bloqueio ?? i.ultima?.motivos?.join("; ") ?? null })) };
  }
  if (issue.dono.length === 0) return { acao: "bloqueado", motivos: [`#${issue.numero} sem dono no go registrado`] };
  const max = p.go.max_iteracoes ?? cfgI.max_iteracoes;
  const iteracao = issue.iteracoes + 1;
  const feedback = issue.ultima?.veredito === "reiterar" ? issue.ultima.feedback : null;

  const antes = instantaneo(cfgI);
  let relatorio = null;
  let erroAgente = null;
  try {
    const h = await kernel.agent(briefing(p, issue, feedback, cfgI), {
      agent: issue.papel,
      label: camel(`Issue ${issue.numero} it${iteracao}`),
      schema: RELATORIO,
    });
    relatorio = await h.wait();
    if (!relatorio || typeof relatorio !== "object") erroAgente = "subagente não devolveu relatório estruturado";
  } catch (e) {
    erroAgente = `subagente falhou: ${String(e?.message ?? e)}`;
  }
  const depois = instantaneo(cfgI);
  const alterados = diferenca(antes, depois);

  const motivos = [];
  let bloqueada = false;
  if (erroAgente) {
    motivos.push(erroAgente);
    bloqueada = true;
  }
  if (antes.head !== depois.head) {
    motivos.push("o subagente alterou o HEAD do git (commit); comitar é do dono");
    bloqueada = true;
  }
  const fora = alterados.filter(c => !dentro(c, issue.dono));
  if (fora.length) {
    motivos.push(`escreveu fora do dono declarado: ${fora.join(", ")}`);
    bloqueada = true;
  }
  const prot = alterados.filter(c => dentro(c, cfgI.protegidos));
  if (prot.length) {
    motivos.push(`tocou caminho protegido: ${prot.join(", ")}`);
    bloqueada = true;
  }
  if (relatorio?.bloqueios?.length) {
    motivos.push(...relatorio.bloqueios.map(b => `subagente bloqueou: ${b}`));
    bloqueada = true;
  }

  const verificacao = bloqueada ? [] : verificar(cfgI);
  for (const v of verificacao) if (v.estado === "sem_verificador") {
    motivos.push(`sem verificador para \`${v.comando}\`: ${v.motivo}`);
    bloqueada = true;
  }
  let julgamento = { falhas: [], achados: [], custo: null };
  const reiterar = [];
  if (!bloqueada) {
    if (alterados.length === 0 && iteracao === 1) reiterar.push("nenhum arquivo foi alterado");
    for (const v of verificacao) if (v.estado === "executado" && v.codigo !== 0) reiterar.push(`\`${v.comando}\` falhou (código ${v.codigo})`);
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
    motivos.push(`esgotou ${max} iteração(ões) sem cobrir todos os critérios`);
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
    testes: verificacao.map(v => ({ comando: v.comando, estado: v.estado, codigo: v.codigo ?? null, saida: v.saida ? cortar(v.saida, 1500, [], "saida") : null })),
    relatorio,
    feedback: feedbackProx,
    modelo: cfg.modelo,
    calibrado: cfg.calibrado,
    recibo,
  });
  return { acao: "iteracao", issue: issue.numero, titulo: issue.titulo, iteracao, max, veredito, motivos, achados: julgamento.achados, arquivos: alterados, testes: verificacao.map(v => `${v.comando}: ${v.estado === "executado" ? `código ${v.codigo}` : v.estado}`), recibo };
}

/** Linha de resumo da saída do verificador (ex.: `1 test, 0 failures`), ou a última linha não vazia. */
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
    `# Implementação — ${p.sprint}`,
    "",
    "Registro por iteração em [`jev.jsonl`](jev.jsonl). A coluna de verificação é o que o orquestrador executou e mediu; o texto de cada critério abaixo é o que o subagente declarou, e foi julgado pelo Jev como consultivo (`calibrado: " + cfg.calibrado + "`). Nenhum commit foi feito; nenhuma issue foi fechada. O dono confere a evidência.",
    "",
  ];
  for (const i of p.issues) {
    const ult = i.ultima;
    l.push(`## #${i.numero} — ${i.titulo}`, "", `- estado: **${i.estado}** em ${i.iteracoes} iteração(ões); papel: \`${i.papel}\`; dono: ${i.dono.map(d => `\`${d}\``).join(", ") || "—"}`);
    if (!ult) {
      l.push(`- sem iteração registrada${i.bloqueio ? `: ${i.bloqueio}` : ""}`, "");
      continue;
    }
    const acumulados = [...new Set(regs.filter(r => r.tipo === "implementacao_iteracao" && r.issue === i.numero).flatMap(r => r.arquivos))].sort();
    l.push(`- arquivos alterados nas iterações (medidos por hash antes e depois): ${acumulados.map(a => `\`${a}\``).join(", ") || "nenhum"}`);
    for (const t of ult.testes) l.push(`- verificação: \`${t.comando}\` → ${t.estado === "executado" ? `código ${t.codigo}${resumoSaida(t.saida)}` : t.estado}`);
    for (const m of ult.motivos) l.push(`- ${ult.veredito === "ok" ? "nota" : "pendência"}: ${m}`);
    const crits = ult.relatorio?.criterios ?? [];
    if (crits.length) l.push("", "Critérios (declarados pelo subagente):");
    for (const c of crits) l.push(`- [${c.evidencia === "execucao" ? "x" : " "}] ${c.criterio} — ${c.atendimento} (evidência: ${c.evidencia}${c.comando ? `; \`${c.comando}\`` : ""})`);
    l.push(`- recibo: \`${ult.recibo}\``, "");
  }
  return l.join("\n");
}

/** Quando não há mais issue a rodar: grava `implementacao.md` (derivado dos registros) e roda o gate. */
export async function fechar(kernel, { sprint, issues }) {
  const cfg = carregarConfig();
  const p = await plano({ sprint, issues });
  if (p.bloqueios.length) return { acao: "bloqueado", motivos: p.bloqueios };
  if (p.proxima) return { acao: "bloqueado", motivos: [`ainda há issue a rodar: #${p.proxima.numero}`] };
  const rel = rel05(sprint, "implementacao.md");
  const existente = lerRel(rel);
  if (existente !== null && !existente.includes(MARCA)) return { acao: "bloqueado", motivos: [`${rel} existe e não foi gerado por este loop; não sobrescrevo`] };
  writeFileSync(join(RAIZ, rel), renderizar(p, registros(sprint), cfg));
  const itens = p.issues.filter(i => i.estado === "ok").flatMap(i => i.criterios.map((c, k) => ({ id: `#${i.numero}.${k + 1}`, texto: c })));
  if (itens.length === 0) return { acao: "fechado", arquivo: rel, gate: "gate pulado: nenhuma issue ok para julgar", veredito: "bloqueado", recibo: null };
  const r = await rodar(kernel, "implementacao", { sprint, itens });
  if (!r.falhas.length) registrar(r, { etapa: "05_implement" });
  return { acao: "fechado", arquivo: rel, gate: textoGate(r), veredito: r.veredito, recibo: r.recibo };
}

/** Texto curto do plano. */
export function painel(p) {
  const l = [`implementação · ${p.sprint} · máx. ${p.max_iteracoes} iteração(ões) por issue · go: ${p.go ? p.go.em : "não registrado"}`];
  for (const b of p.bloqueios) l.push(`BLOQUEIO  ${b}`);
  for (const i of p.issues) {
    l.push(`  #${i.numero} [${i.estado}${i.iteracoes ? ` it${i.iteracoes}` : ""}] ${i.titulo.slice(0, 60)} · ${i.criterios.length} critério(s) · deps: ${i.deps.map(d => `#${d}`).join(",") || "—"} · papel ${i.papel} · dono: ${i.dono.join(", ") || "—"}${i.bloqueio ? `\n      BLOQUEIO ${i.bloqueio}` : ""}`);
  }
  if (p.proxima) l.push(`próxima: #${p.proxima.numero}`);
  return l.join("\n");
}
