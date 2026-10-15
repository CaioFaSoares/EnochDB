---
description: Conduz o ICM do EnochDB com o Jev: status, continue, duck (backlog), decidir (decisão do dono sobre o recibo) e implement (loop da sprint)
argument-hint: "[status|continue|duck|decidir|implement] [sprint | tema do duck | aceito|rejeitado|ajustado]"
---

Conduza o ICM do EnochDB. Modo: `$1` (vazio = `status`). Resto dos argumentos: `$@[2]`. Regras do Jev e dos módulos: `docs/agents/jev.md`. Execute **só a seção do modo pedido**. O cwd da sessão deve ser a raiz do repositório.

Regras que valem em todos os modos: o painel e qualquer veredito do Jev são consultivos (cada `ACHADO` ou `INCERTO` se confirma no artefato antes de virar fala sua); `BLOQUEIO` é falha de ferramenta, artefato ou estado: diga qual e pare nessa frente; a ordem das etapas e o "próximo" vêm do código; fechar etapa e issue, mover arquivo de `_backlog/` e comitar são atos do dono. Responda em pt-BR, curto.

## status (padrão)

```js
const c = await import(`${process.cwd()}/docs/_index/icm-conduzir.mjs`);
const sprint = "$2" || c.sprints().at(-1);
globalThis.P = await c.conduzir({ judge, judgeBatch }, { sprint });
console.log(c.painel(P));
```

Mostre ao dono: etapa atual, veredito e recibo do gate, issues prontas e a refinar (com a pergunta do Jev que falhou) e o próximo passo. O `conduzir` grava o recibo do gate em `handovers/jev.jsonl` (idempotente pelo recibo); informe `P.gate.registrado`. Não chame `registrar`. Se `P.task` existir, pergunte (`ask`) o go, o papel (a sugestão do Jev é só sugestão) e o **dono de cada arquivo**, um por arquivo; com o go, chame o tool `task` com `P.task`. Sem go, nada é despachado.

## continue

Avance **um passo** da etapa atual, sem pular gate humano.

1. Rode o painel acima (sem despachar). Pegue `P.proximo[0]`.
2. Se for **produzir o handover** da etapa: leia o contrato `docs/<etapa>/CONTEXT.md`, as entradas dele e a issue em foco (`gh issue view`); escreva o handover com os papéis candidatos de `P` quando precisar de leitura ou revisão. Um escritor por arquivo.
3. Se for **achados do gate**: abra cada artefato citado, confirme, corrija ou registre cada um; rode o gate de novo.
4. Se o próximo for **levar o recibo ao dono**: pare e apresente o recibo; o gate humano é dele. Se for `05_implement`, o caminho é `/icm implement`, não este modo.
5. Termine mostrando o painel novo e o que falta para o gate humano. O `conduzir` já gravou o recibo do gate em `handovers/jev.jsonl`; não chame `registrar` com `P.gate`. `registrarDecisao` só depois do dono decidir. O hook do omp (`.omp/hooks/pre/icm-jev.ts`) avisa quando o artefato muda depois do recibo: rode o gate de novo.

## duck

Conversa para explorar `$@[2]` e, se valer, guardar no backlog. Backlog é `docs/_backlog/` (ver `docs/_backlog/README.md`); posicionar numa sprint ainda não iniciada é mover o arquivo, ato do dono.

1. Converse com o dono para delimitar **uma** dúvida. Quando precisar de prova, chame o papel `11-discovery-rubberduck` (tool `task`, `agent: "11-discovery-rubberduck"`) com a dúvida em uma frase, o que já foi tentado e os caminhos autorizados; ele devolve âncoras `arquivo:linha`. Não responda por analogia: sem âncora, diga "não encontrei".
2. Quando o dono pedir para guardar, monte o item e **prévia sem escrever**:

   ```js
   const B = await import(`${process.cwd()}/docs/_index/icm-duck.mjs`);
   globalThis.V = await B.prever({ judge, judgeBatch }, { titulo, pergunta, resumo, evidencias: [{ ancora: "arquivo:linha", trecho: "texto exato da linha" }], contradicoes: [], em_aberto: [] });
   console.log(B.texto(V));
   ```

   `BLOQUEIO` (âncora que não bate, juiz falhou) impede a gravação: corrija a âncora ou grave sem ela como ideia. Mostre ao dono a prévia e o épico sugerido; ele pode trocar título, recorte ou descartar.
3. Com o ok do dono (`ask`), `B.gravar(V)`. Informe o caminho, as sprints ainda não iniciadas (`V.candidatas`) e o comando de posicionar: `git mv docs/_backlog/<arquivo> docs/_sprints/<sprint>/01_grilling/inputs/`. Não mova você.

## implement

Loop de implementação de **todas as issues da sprint**, uma por vez, em ordem de dependência, com verificação e Jev em cada iteração. Só vale em `05_implement`. Mecanismo e garantias: `docs/agents/jev.md`, seção Implementar.

1. **Plano e go.** Descubra a sprint (`$2` ou a mais recente) e rode:

   ```js
   const I = await import(`${process.cwd()}/docs/_index/icm-implementar.mjs`);
   globalThis.I = I;
   globalThis.SPRINT = "$2" || (await import(`${process.cwd()}/docs/_index/icm-conduzir.mjs`)).sprints().at(-1);
   const p = await I.plano({ sprint: SPRINT });
   console.log(I.painel(p)); console.log(JSON.stringify(p.proposta));
   ```

   `BLOQUEIO` aqui para o modo (etapa errada, sem `#N` em `tickets.md`, issue sem critérios, ciclo). Se `p.go` já existe, retome do passo 3. Senão, mostre ao dono, via `ask`, a ordem, o papel e o **dono de caminhos de cada issue** (parta de `p.proposta`; ele edita), e o limite de iterações (`p.max_iteracoes`). Sem dono de caminhos declarado, não há go. Com o go: `I.registrarGo({ sprint: SPRINT, itens: [{ numero, papel, dono: ["lib/...", "test/..."] }] })` e ponha `status: em-curso` na ficha `docs/_sprints/<sprint>/05_implement/CONTEXT.md` se ainda estiver `vazio`.

2. **Verificador.** O loop roda `conducao.implementacao.verificacao` de `docs/agents/jev-gates.json` (hoje `mix test`, exige `mix.exs`). Ferramenta ausente é `bloqueada`, nunca fallback.

3. **Loop.** Repita uma célula por passo, com `timeout: 1800`:

   ```js
   globalThis.R = await I.passo({ judge, judgeBatch, agent }, { sprint: SPRINT });
   console.log(JSON.stringify(R, null, 1));
   ```

   - `iteracao` com `veredito: "ok"`: próxima. `"reiterar"`: o feedback já foi gravado; chame de novo. `"bloqueada"`: o motivo está em `R.motivos`; o loop segue para as issues independentes sozinho.
   - Entre issues, diga ao dono uma linha: `#N it/máx veredito`, arquivos e `testes`. Não interrompa para perguntar, a menos que `R.acao` seja `bloqueado` ou `sem_go`.
   - Pare e traga ao dono se o mesmo motivo bloquear duas issues seguidas, se aparecer `escreveu fora do dono`, `tocou caminho protegido` ou `alterou o HEAD`: são violação de contrato, não falha de teste.
   - `R.acao === "fim"`: vá ao passo 4.

4. **Fechamento.** `await I.fechar({ judge, judgeBatch }, { sprint: SPRINT })` grava `05_implement/handovers/implementacao.md` (derivado de `jev.jsonl`) e roda o gate `implementacao`. Mostre ao dono: issues `ok`, issues `bloqueada` ou pendentes com o motivo, o veredito e o recibo do gate, e o que **não** foi feito: nenhum commit, nenhuma issue fechada, etapa ainda `em-curso`. O gate humano do `05_implement` e o commit são do dono. Não repasse o texto dos critérios que o subagente declarou como se fosse verificado: a verificação medida é a linha `verificação` do arquivo.

## decidir

Registra a decisão do dono sobre o recibo que ele viu, para o gate da etapa atual, e propaga o resultado. Argumento: `$2` ∈ `aceito|rejeitado|ajustado`, dito pelo dono; sem ele, pare e peça. O agente nunca escolhe a decisão. Aqui `$2` é a decisão, nunca a sprint: a sprint é sempre a mais recente.

1. Confira o frescor **sem chamar o Jev** (não rode o `conduzir`, que grava recibo novo se o texto mudou):

   ```js
   const c = await import(`${process.cwd()}/docs/_index/icm-conduzir.mjs`);
   const g = await import(`${process.cwd()}/docs/_index/jev-gate.mjs`);
   globalThis.SPRINT = c.sprints().at(-1);
   globalThis.ETAPA = c.etapaAtual(g.fatosDoSprint(SPRINT)).nome;
   globalThis.F = g.frescor(SPRINT, ETAPA);
   console.log(JSON.stringify(F));
   ```

   Com `F.estado !== "atual"`, pare: diga ao dono o estado (`desatualizado` lista `F.mudados`) e que o `/icm status` grava o recibo novo para ele ver antes de decidir. Com `atual`, o recibo é `F.recibo` (o último `veredito` do `jev.jsonl`) e `F.veredito` é o que o dono viu.
2. Registre a decisão sobre esse recibo:

   ```js
   console.log(g.registrarDecisao({ sprint: SPRINT, etapa: ETAPA, recibo: F.recibo, decisao: "$2" }));
   ```

3. Só com `aceito` ou `ajustado`: troque `Status: proposta` por `aceita` nas ADRs que o recibo cobre (as `docs/adr/NNNN-*.md` linkadas pelo handover da etapa). Com `ajustado`, só nas que o dono listar. Com `rejeitado`, nada muda: o dono diz o que corrigir.
4. Ainda com a etapa aberta, grave o recibo do texto final: trocar o status das ADRs muda os artefatos que o gate lê, e depois de fechar a ficha o `conduzir` passa à etapa seguinte e não roda mais esse gate. A decisão do passo 2 continua no recibo anterior; este só registra o texto depois da troca:

   ```js
   const r = await g.rodar({ judge, judgeBatch }, F.gate, { sprint: SPRINT });
   console.log(r.veredito, r.recibo, JSON.stringify(g.registrar(r)));
   ```

5. Fechar a etapa é ato do dono: pergunte (`ask`) se fecha. Só com sim, ponha `status: fechado` na ficha `docs/_sprints/<sprint>/<etapa>/CONTEXT.md`; o hook pede a confirmação do dono nessa edição. Fechar a issue e comitar continuam com o dono.
6. Mostre o painel, com a sprint explícita (o snippet do `status` usa `$2`, que aqui é a decisão): `globalThis.P = await c.conduzir({ judge, judgeBatch }, { sprint: SPRINT }); console.log(c.painel(P));`. Diga ao dono qual é o recibo da decisão (passo 2) e qual é o do texto final (passo 4).
