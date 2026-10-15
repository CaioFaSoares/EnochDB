// Condutor do ICM do EnochDB. Ver docs/agents/jev.md §Conduzir.
//
// Uma chamada devolve: etapa atual (derivada em código), veredito do gate dessa
// etapa (Jev), leitura de cada issue aberta (Jev) e, para as issues prontas, um
// pacote `task` pronto para o orquestrador despachar a subagentes do roster.
//
//   const c = await import(`${process.cwd()}/docs/_index/icm-conduzir.mjs`);
//   const p = await c.conduzir({ judge, judgeBatch }, { sprint: "s01-nucleo-enoch" });
//   console.log(c.painel(p));   // p.task é o argumento do tool `task`
//
// Quem decide é código e o dono: a ordem das etapas, o próximo passo, quais
// papéis são candidatos e se uma issue está pronta saem de regras sobre os
// vereditos. O Jev só dá probabilidades (D5 do handoff). A sugestão de papel é
// consultiva e restrita aos candidatos da etapa; abaixo da confiança mínima
// fica sem sugestão e o dono escolhe. Nada aqui escreve em docs/ nem cria issue.
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
      falhas.push(`papel ausente no roster: ${id}`);
      continue;
    }
    const t = lerRel(`.omp/agents/${id}.md`);
    const descricao = campo(t, "description");
    if (!descricao) falhas.push(`papel sem description: ${id}`);
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
    return { falha: `gh issue list falhou: ${String(e.stderr || e.message).trim().split("\n")[0]}` };
  }
}

export const caminhosCitados = corpo =>
  [...new Set([...(corpo ?? "").matchAll(/`?((?:docs|lib|test|config|priv|examples)\/[\w./{}-]+\.\w+|CONTEXT\.md)`?/g)].map(m => m[1]))];

/** Etapa atual: primeira que não está fechada nem não aplicável. `null` se todas estão. */
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
      instructions: `A issue é um item da etapa ${etapa}. Qual papel do roster é o mais adequado para executá-la?`,
      criteria: {
        ...Object.fromEntries(papeis.map(p => [p.id, p.descricao])),
        nenhum: "Nenhum dos papéis acima descreve o trabalho que a issue pede.",
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
      avisos.push(`#${issue.number}: sem resposta para ${p.id}`);
      classes.push("achado");
      continue;
    }
    perguntas[p.id] = valor;
    if (p.ruim_se) classes.push(classificar(valor, p.ruim_se, faixa));
  }
  const prontidao = classes.includes("achado") ? "refinar" : classes.includes("incerto") ? "incerta" : "pronta";
  let papel = null;
  if (papeis.length === 1) papel = { id: papeis[0].id, confianca: null, origem: "unico candidato da etapa" };
  else if (resp?.papel?.choice) {
    const { choice, confidence, probabilities } = resp.papel;
    const topo = probabilities?.[choice] ?? 0;
    if (choice !== "nenhum" && confidence >= cfgC.confianca_minima_papel && topo >= cfgC.confianca_minima_papel)
      papel = { id: choice, confianca: Number(confidence.toFixed(2)), origem: "jev" };
    else papel = { id: null, tentativa: choice, confianca: Number((confidence ?? 0).toFixed(2)), origem: "abaixo da confiança mínima" };
  }
  return { numero: issue.number, titulo: issue.title, url: issue.url, perguntas, prontidao, papel };
}

/** Contexto compartilhado de qualquer despacho do ICM; uma casa só para as regras dos subagentes. */
export function contextoCompartilhado(sprint, etapa) {
  return [
    "# Goal",
    `Sprint ${sprint}, etapa ${etapa}. Cada tarefa é uma issue do tracker do repositório.`,
    "",
    "# Contract",
    "- Leia antes de agir: `CONTEXT.md`, `docs/canon.md`, `docs/agents/README.md`, o contrato da etapa em `docs/" + etapa + "/CONTEXT.md` e os ADRs que tocam a área.",
    "- Use o vocabulário do glossário. Se a issue contradisser um ADR, exponha o conflito e pare; não reescreva decisão.",
    "- Papéis de leitura não escrevem arquivo: devolvem o resultado a quem pediu. Quem escreve só toca os arquivos que o orquestrador declarou como seus antes do despacho.",
    "- Evidência diz como foi obtida: `leitura` ou `execução`. Nada de verificação não observada.",
    "- Fechar etapa, mudar `status:` e publicar issue são atos do dono.",
    "- Perguntas e limiares do Jev: `docs/agents/jev-gates.json`. Não crie outros e não os edite.",
  ].join("\n");
}

function pacoteTask(plano, etapa) {
  const prontas = plano.issues.filter(i => i.prontidao === "pronta" && i.papel?.id);
  if (prontas.length === 0) return null;
  const contexto = contextoCompartilhado(plano.sprint, etapa);
  const tasks = prontas.map(i => {
    const caminhos = i.caminhos.length ? i.caminhos.map(c => `\`${c}\``).join(", ") : "nenhum citado";
    return {
      agent: i.papel.id,
      name: camel(`Issue ${i.numero} ${i.papel.id.replace(/^\d+-/, "")}`),
      solutionSpace: "issue delimitada com critério de aceite; a abordagem fica aberta dentro do critério",
      task: [
        "# Target",
        `Issue #${i.numero}: ${i.titulo}. Leia o corpo com \`gh issue view ${i.numero}\` (cwd na raiz do repositório); ele não foi copiado aqui.`,
        `Caminhos citados na issue (existem): ${caminhos}.`,
        "",
        "# Change",
        `Entregue só o que a issue #${i.numero} pede, dentro da etapa ${etapa}. Arquivos que você pode escrever: os que o orquestrador declarar no despacho; sem dono declarado, não edite.`,
        "",
        "# Acceptance",
        `Cada critério de aceite da issue #${i.numero} com a evidência (\`leitura\` ou \`execução\`) e o que ficou sem prova.`,
      ].join("\n"),
    };
  });
  return { i: `Despachando ${tasks.length} issue(s) da etapa ${etapa}`, context: contexto, tasks };
}

/**
 * Painel de condução. `args`: { sprint, issues?: boolean (padrão true), gate?: boolean (padrão true) }.
 * Nunca lança por falha de judge, artefato ou gh: devolve `bloqueios`.
 */
export async function conduzir(kernel, args = {}) {
  const { sprint } = args;
  if (!sprint) throw new Error("`sprint` é obrigatório");
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
  if (!atual) {
    plano.proximo.push("Todas as etapas estão fechadas ou não aplicáveis: a sprint está fechada (derivado). Nada a conduzir.");
    return plano;
  }

  // 1. Gate da etapa atual, só quando há handover para julgar.
  const nomeGate = cfgC.gate_por_etapa[atual.nome];
  const handover = cfgC.handover_por_etapa[atual.nome];
  const g = cfg.gates[nomeGate];
  const alvos = Object.values(g.artefatos ?? {}).map(t => t.replaceAll("{sprint}", sprint));
  const faltam = alvos.filter(rel => lerRel(rel) === null);
  if (args.gate === false) plano.gate = { pulado: true };
  else if (faltam.length) plano.gate = { pulado: true, motivo: `sem ${faltam.map(f => f.split("/").pop()).join(", ")}` };
  else {
    const r = await rodar(kernel, nomeGate, { sprint });
    // Recibo só de veredito real: bloqueio não é veredito (ver frescor em jev-gate.mjs).
    const recibo = r.falhas.length ? { gravado: false } : registrar(r, { etapa: atual.nome });
    plano.gate = { nome: nomeGate, veredito: r.veredito, recibo: r.recibo, registrado: recibo.gravado, texto: textoGate(r), achados: r.achados.length, falhas: r.falhas };
    plano.bloqueios.push(...r.falhas.map(f => `gate ${nomeGate}: ${f}`));
  }

  // 2. Issues abertas lidas pelo Jev, com papéis candidatos da etapa.
  if (args.issues !== false) {
    const { papeis, falhas } = papeisDoRoster(cfgC.papeis_por_etapa[atual.nome] ?? []);
    plano.bloqueios.push(...falhas);
    const lista = issuesAbertas();
    if (lista.falha) plano.bloqueios.push(lista.falha);
    else if (papeis.length === 0) plano.bloqueios.push(`sem papéis candidatos para ${atual.nome}`);
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
      for (const [k, msg] of Object.entries(erro)) plano.bloqueios.push(`issue #${k}: judge falhou: ${msg}`);
      const avisos = [];
      for (const i of lista.issues) {
        if (!ok[String(i.number)]) continue;
        const lida = lerIssue(i, ok[String(i.number)], cfg, cfgC, papeis, avisos);
        lida.caminhos = caminhosCitados(i.body).filter(c => !c.includes("{") && existsSync(join(RAIZ, c)));
        lida.hash = sha(`${i.title}\n${i.body ?? ""}`).slice(0, 12);
        plano.issues.push(lida);
      }
      plano.bloqueios.push(...avisos);
      plano.truncamentos = trunc;
    }
  }

  // 3. Próximo passo: regra sobre os fatos, nunca escolha do Jev.
  if (fatos.falhas.length) plano.proximo.push("Corrigir as inconsistências de estado listadas em bloqueios antes de qualquer outra coisa.");
  if (plano.gate?.pulado && plano.gate.motivo) plano.proximo.push(`Produzir handovers/${handover} da etapa ${atual.nome} (contrato: docs/${atual.nome}/CONTEXT.md).`);
  else if (plano.gate?.achados) plano.proximo.push(`Ler os ${plano.gate.achados} achado(s) do gate ${nomeGate} no artefato e resolver ou registrar cada um.`);
  else if (plano.gate?.veredito === "sem_achados") plano.proximo.push(`Levar o recibo ${plano.gate.recibo} ao dono para o gate humano de ${atual.nome}; sem_achados não é aprovação.`);
  const prontas = plano.issues.filter(i => i.prontidao === "pronta");
  const refinar = plano.issues.filter(i => i.prontidao !== "pronta");
  const comPapel = prontas.filter(i => i.papel?.id);
  const semPapel = prontas.filter(i => !i.papel?.id);
  if (refinar.length) plano.proximo.push(`Refinar com o dono: ${refinar.map(i => `#${i.numero} (${i.prontidao})`).join(", ")}.`);
  if (comPapel.length) plano.proximo.push(`Pedir o go do dono e declarar o dono de cada arquivo antes de despachar: ${comPapel.map(i => `#${i.numero}`).join(", ")}.`);
  if (semPapel.length) plano.proximo.push(`Prontas sem papel sugerido (${semPapel.map(i => `#${i.numero}`).join(", ")}): o dono escolhe o papel ou o orquestrador executa; não há despacho montado.`);
  if (atual.nome === "05_implement") plano.proximo.push("Implementar as issues da sprint em loop com verificação: `/icm implement` (o despacho avulso fica desligado nesta etapa).");
  plano.task = atual.nome === "05_implement" ? null : pacoteTask(plano, atual.nome);
  return plano;
}

/** Texto curto para o humano e para o orquestrador. */
export function painel(p) {
  const l = [`ICM · ${p.sprint} · etapa atual: ${p.etapa ?? "nenhuma"} (derivado) · ${p.modelo} · calibrado: ${p.calibrado}`];
  l.push(p.etapas.map(e => `${e.nome.slice(0, 2)}:${e.status}`).join("  "));
  for (const b of p.bloqueios) l.push(`BLOQUEIO  ${b}`);
  if (p.gate) {
    if (p.gate.pulado) l.push(`gate: pulado${p.gate.motivo ? ` (${p.gate.motivo})` : ""}`);
    else l.push("", p.gate.texto);
  }
  if (p.issues.length) {
    l.push("", "issues abertas (leitura do Jev; consultiva):");
    for (const i of p.issues) {
      const papel = i.papel?.id ? `${i.papel.id}${i.papel.confianca != null ? ` (${i.papel.confianca})` : ""}` : `sem sugestão${i.papel?.tentativa ? ` [${i.papel.tentativa} ${i.papel.confianca}]` : ""}`;
      const q = Object.entries(i.perguntas).map(([k, v]) => `${k}=${v.toFixed(2)}`).join(" ");
      l.push(`  #${i.numero} ${i.prontidao.toUpperCase().padEnd(7)} ${papel} · ${i.titulo.slice(0, 70)}`, `      ${q}`);
    }
  }
  if (p.proximo.length) l.push("", "próximo:", ...p.proximo.map((x, n) => `  ${n + 1}. ${x}`));
  if (p.task) l.push("", `despacho pronto: p.task (${p.task.tasks.length} tarefa(s): ${p.task.tasks.map(t => `${t.name}→${t.agent}`).join(", ")})`);
  return l.join("\n");
}

/** Lista as sprints existentes, para o comando sem argumento. */
export function sprints() {
  const d = join(RAIZ, "docs/_sprints");
  return existsSync(d) ? readdirSync(d, { withFileTypes: true }).filter(e => e.isDirectory()).map(e => e.name).sort() : [];
}
