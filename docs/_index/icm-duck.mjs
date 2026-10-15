// Backlog do `/icm duck`. Ver docs/_backlog/README.md e docs/agents/jev.md §Duck.
//
// A conversa com o rubberduck explora uma dúvida; o que vale guardar vira um
// arquivo em docs/_backlog/. Este módulo só valida e grava; quem conversa e
// decide o que entra é o orquestrador com o dono.
//
//   const B = await import(`${process.cwd()}/docs/_index/icm-duck.mjs`);
//   const v = await B.prever({ judge, judgeBatch }, { titulo, pergunta, evidencias, contradicoes, em_aberto });
//   console.log(B.texto(v));          // o dono lê antes de qualquer escrita
//   B.gravar(v);                      // só depois do ok do dono; recusa se houver bloqueio
//
// Garantias em código: toda âncora `arquivo:linha` é aberta e o trecho citado
// precisa estar na linha; item sem âncora é gravado como ideia, nunca como fato;
// o épico sugerido é consultivo (Jev, abaixo da confiança mínima fica `—`);
// posicionar numa sprint é mover o arquivo, ato do dono.
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
  if (!m) return `âncora inválida (esperado arquivo:linha): ${ancora}`;
  const abs = resolve(RAIZ, m[1]);
  if (abs !== ALEPH && !abs.startsWith(RAIZ + sep) && !abs.startsWith(ALEPH + sep)) return `âncora fora de ${ALEPH}: ${ancora}`;
  if (abs.split(sep).includes(".git")) return `âncora em .git: ${ancora}`;
  if (!existsSync(abs)) return `arquivo da âncora não existe: ${ancora}`;
  const linhas = readFileSync(abs, "utf8").split("\n");
  const n = Number(m[2]);
  if (n < 1 || n > linhas.length) return `linha fora do arquivo (${linhas.length} linhas): ${ancora}`;
  if (!trecho || !norm(linhas[n - 1]).includes(norm(trecho))) return `o trecho não está na linha ${n} de ${m[1]}: "${trecho}"`;
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

/** Sprints sem nenhuma etapa iniciada: candidatas a receber o item. Derivado das fichas. */
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
    `epico_sugerido: ${v.epico ?? "—"} # consultivo (Jev${v.epico_confianca != null ? `, confiança ${v.epico_confianca}` : ""}); quem posiciona é o dono`,
    ...(v.evidencias.length ? [] : ["sem_ancora: true # ideia, não fato"]),
    "---",
    "",
    `# ${v.id} — ${v.titulo}`,
    "",
    "## Pergunta",
    "",
    v.pergunta,
    "",
  ];
  if (v.resumo) l.push("## O que se sabe", "", v.resumo, "");
  if (v.evidencias.length) {
    l.push("## Âncoras", "");
    for (const e of v.evidencias) l.push(`- \`${e.ancora}\` — ${e.trecho}`);
    l.push("");
  }
  if (v.contradicoes.length) l.push("## Contradições", "", ...v.contradicoes.map(c => `- ${c}`), "");
  if (v.em_aberto.length) l.push("## Em aberto", "", ...v.em_aberto.map(c => `- ${c}`), "");
  l.push(
    "## Como posicionar",
    "",
    "Mover este arquivo para `docs/_sprints/<sprint>/01_grilling/inputs/` de uma sprint ainda não iniciada (`git mv`). Sair daqui é o posicionamento; ninguém declara a sprint de destino dentro do arquivo.",
    "",
  );
  return l.join("\n");
}

/**
 * Valida e prepara o item sem escrever nada. `args`: { titulo, pergunta, resumo?, evidencias?, contradicoes?, em_aberto? }.
 * `evidencias`: [{ ancora: "arquivo:linha", trecho }]. Devolve `bloqueios` se algo não se sustenta.
 */
export async function prever(kernel, args) {
  const cfg = carregarConfig();
  const cfgB = cfg.conducao.backlog;
  const { titulo, pergunta, resumo = "", evidencias = [], contradicoes = [], em_aberto = [] } = args ?? {};
  const v = { id: proximoId(), titulo, pergunta, resumo, evidencias, contradicoes, em_aberto, data: new Date().toISOString().slice(0, 10), bloqueios: [], achados: [], epico: null, epico_confianca: null, truncamentos: [] };
  if (!titulo?.trim()) v.bloqueios.push("sem título");
  if (!pergunta?.trim()) v.bloqueios.push("sem pergunta");
  if (v.bloqueios.length) return v;
  for (const e of evidencias) {
    const erro = resolverAncora(e);
    if (erro) v.bloqueios.push(erro);
  }
  v.arquivo = `${DIR}/${v.id}-${slug(titulo)}.md`;
  if (existsSync(join(RAIZ, v.arquivo))) v.bloqueios.push(`já existe: ${v.arquivo}`);
  if (v.bloqueios.length) return v;
  v.md = renderizar(v);

  const estado = cortar(v.md, cfg.limite_estado_chars, v.truncamentos, v.arquivo);
  const epicos = epicosAbertos();
  const questions = perguntasBool(cfgB.perguntas);
  if (epicos.length) {
    questions.epico = {
      type: "choice",
      instructions: "A qual épico aberto este item do backlog pertence?",
      criteria: { ...Object.fromEntries(epicos.map(e => [e.id, e.titulo])), nenhum: "Nenhum dos épicos abertos descreve o assunto do item." },
    };
  }
  const { ok, erro } = await lote(kernel, { item: { item: estado } }, questions, `backlog ${v.id}`);
  for (const m of Object.values(erro)) v.bloqueios.push(`judge falhou: ${m}`);
  const r = ok.item;
  if (r) {
    for (const q of cfgB.perguntas) {
      const x = r[q.id]?.bool;
      if (typeof x !== "number") {
        v.bloqueios.push(`sem resposta para ${q.id}`);
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

/** Grava o item. Recusa se `prever` devolveu bloqueio. Só depois do ok do dono. */
export function gravar(v) {
  if (v.bloqueios?.length) throw new Error(`não gravo com bloqueio: ${v.bloqueios.join("; ")}`);
  const abs = join(RAIZ, v.arquivo);
  if (existsSync(abs)) throw new Error(`já existe: ${v.arquivo}`);
  mkdirSync(join(RAIZ, DIR), { recursive: true });
  writeFileSync(abs, v.md);
  return { arquivo: v.arquivo };
}

export function texto(v) {
  const l = [`backlog · ${v.id ?? "—"} · ${v.titulo ?? "(sem título)"}`];
  for (const b of v.bloqueios) l.push(`BLOQUEIO  ${b}`);
  for (const a of v.achados) l.push(`${a.classe === "achado" ? "ACHADO   " : "INCERTO  "} ${a.pergunta} = ${a.valor.toFixed(2)}`);
  if (!v.bloqueios.length) {
    l.push(`arquivo: ${v.arquivo}`, `âncoras verificadas em código: ${v.evidencias.length}${v.evidencias.length ? "" : " (grava como ideia, sem fato)"}`, `épico sugerido: ${v.epico ?? "—"}${v.epico_confianca != null ? ` (${v.epico_confianca})` : ""}`);
    l.push(`sprints ainda não iniciadas: ${v.candidatas?.length ? v.candidatas.join(", ") : "nenhuma (crie uma pelo PROCESS.md, \"Abrir uma sprint\")"}`);
  }
  return l.join("\n");
}
