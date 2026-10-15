# Jev no ICM do EnochDB

O Jev (TypeSafe System One, `jev-latest`) é a **camada de julgamento** dos gates do ICM deste repositório. Ele confere estado, cobertura e evidência antes de o dono ler; não decide nada. A pesquisa que fundamenta o desenho está no `_Aleph`: `_research/AlephBible/chat.md:379-508` (decisões D5–D13, restrições §6, resultados §7). Aqui só se diz como ela se aplica.

## Peças

| Peça | Caminho | Papel |
| --- | --- | --- |
| Papel `judge` | [`../../.omp/config.yml`](../../.omp/config.yml), `modelRoles.judge` | aponta o `judge()` do `eval` do omp para `typesafe/jev-latest` |
| Perguntas e limiares | [`jev-gates.json`](jev-gates.json) | **único** arquivo que o dono revisa; nada de pergunta ou limiar em outro lugar |
| Runner | [`../_index/jev-gate.mjs`](../_index/jev-gate.mjs) | monta o `state`, chama o Jev, combina em código, devolve veredito |
| Condutor | [`../_index/icm-conduzir.mjs`](../_index/icm-conduzir.mjs) | deriva a etapa atual, roda o gate dela, lê as issues abertas e monta o despacho de subagentes |
| Implementação | [`../_index/icm-implementar.mjs`](../_index/icm-implementar.mjs) | loop por issue: plano, go, passo (despacho + medição + verificação + Jev), fechamento |
| Backlog | [`../_index/icm-duck.mjs`](../_index/icm-duck.mjs) | valida âncoras e grava `docs/_backlog/Bnn-*.md` |
| Comando | [`../../.omp/commands/icm.md`](../../.omp/commands/icm.md) | `/icm [status\|continue\|duck\|implement] [sprint \| tema]` |
| Hook | [`../../.omp/hooks/pre/icm-jev.ts`](../../.omp/hooks/pre/icm-jev.ts) | guarda de escrita, frescor do gate e turno de parada; ver "Hooks do omp" |
| Recibo | `docs/_sprints/{sprint}/{etapa}/handovers/jev.jsonl` | uma linha por veredito e uma por decisão humana; só `registrar`/`registrarDecisao` escrevem |

A chave da TypeSafe fica na credencial do omp (`typesafe`), nunca em arquivo do repositório.

## Gates

| Gate | Quando | O que confere |
| --- | --- | --- |
| `estado` | início de sessão e antes de dizer "pronto" | fichas × pastas × handovers; ordem das etapas em código, coerência ficha × handover pelo Jev |
| `grilling` | antes do gate humano do `01_grilling` | decisão fechada sem origem; pergunta aberta dentro de decisão fechada |
| `dominio` | antes do gate humano do `02_domain` | ADR só com a solução (lê os ADRs linkados pelo handover); termo sem aprovação; decisão sem casa |
| `spec` | antes do gate humano do `03_spec` | cada decisão `Dn` do grilling aparece na spec e nenhuma é contradita |
| `tickets` | antes de publicar | cada item da spec é entregue por algum ticket |
| `implementacao` | antes de pedir o gate do `05_implement` | cada critério tem execução registrada; alegação sem comando |
| `revisao` | antes do gate do `06_review` | achado sem evidência ou sem destino; verificação sem comando |
| `handoff` | antes do gate do `07_handoff` | teste de contexto zero; execução alegada sem prova |
| `opcoes` | quando houver mais de um caminho viável | cada opção × cada critério, ranking e empate em código |

## Como chamar

Dentro do `eval` (JS) do omp, com o cwd em `EnochDB/` para valer o papel `judge`:

```js
const g = await import(`${process.cwd()}/docs/_index/jev-gate.mjs`);
const r = await g.rodar({ judge, judgeBatch }, "spec", { sprint: "s01-nucleo-enoch" });
console.log(g.texto(r));
```

- `rodar(kernel, gate, args)` — `args.sprint` obrigatório, exceto em `opcoes` (`decisao`, `opcoes`, `criterios`, `contexto`). Para `cobertura`, `args.itens` (`[{id, texto}]`) substitui a extração automática.
- `registrar(r)` — acrescenta o veredito ao `jev.jsonl` da etapa; idempotente pelo `recibo`.
- `registrarDecisao({sprint, etapa, recibo, decisao})` — **só depois** de o dono dizer `aceito`, `rejeitado` ou `ajustado`. É o par `(veredito, decisão humana)` da D7 do handoff; o agente não o escolhe.

Veredito: `bloqueado` (ferramenta, artefato, extração ou judge falhou), `revisar` (há achado ou incerto) ou `sem_achados`. `sem_achados` **não** é aprovação.

## Hooks do omp

O hook `.omp/hooks/pre/icm-jev.ts` (descoberta ambiente do omp; vale com o cwd em `EnochDB/`) faz o fluxo acontecer sem o agente lembrar. Ele **não chama o Jev**: o Jev continua rodando no `eval`, pelo `conduzir`; o hook garante que isso aconteça no momento certo. Tudo é derivado das fichas, dos arquivos e dos recibos (A4).

| Evento | O que faz | Quem sofre |
| --- | --- | --- |
| `tool_call` (`edit`/`write`) | **Guarda.** Bloqueia escrita em `conducao.guarda.proteger` (`jev-gates.json`, `docs/_index/`, o próprio hook, `icm.md`), em `jev.jsonl` à mão e `status: fechado` em ficha de etapa. Com UI, o agente principal pergunta ao dono; sem UI e em subagente, bloqueia. | todos |
| `tool_result` (`edit`/`write`) | **Frescor.** Se o handover da etapa vigente (ou um ADR, na `02_domain`) mudou desde o último recibo, devolve como contexto confiável a instrução de rodar o gate, uma vez por turno. | agente principal |
| `agent_end` | **Parada.** Se ainda há gate sem recibo ou desatualizado, dispara um turno (`sendMessage` com `triggerTurn`) com a mesma instrução. Uma vez por estado: não entra em laço. | agente principal |
| `session_start`, `agent_end` | **Status.** Linha no rodapé: `ICM <sprint> · <etapa> · <gate>: <frescor>`. | UI |

- **Frescor** (`frescor(sprint, etapa)` em `jev-gate.mjs`): compara o hash atual dos artefatos que o gate lê com o do último recibo `veredito` do gate. `sem_recibo` e `desatualizado` avisam; `sem_artefato` (nada a julgar) e `atual` não. Recibo bloqueado nunca é gravado, então não vale como recibo.
- **O recibo agora nasce do `conduzir`.** Ele grava o veredito real do gate da etapa (idempotente pelo `recibo`); o agente não precisa chamar `registrar`. A decisão do dono continua só em `registrarDecisao`.
- **`dominio` lê os ADRs.** O gate lê o `adrs.md` **e cada `docs/adr/NNNN-*.md` que ele linka** (`artefatos_citados`); ADR citado que não existe bloqueia. Editar só um ADR já torna o gate desatualizado.
- `05_implement` fica fora do aviso: o recibo dela nasce em `fechar` do `/icm implement`.
- O hook falha em silêncio em `tool_result` e `agent_end` (só deixa de avisar) e fecha em `tool_call`. Para manter a casa única, a lista de caminhos protegidos mora em `jev-gates.json` (`conducao.guarda`).
- Manutenção: editar o próprio sistema (`docs/_index/`, hook, `jev-gates.json`) pede confirmação do dono; sem UI, edite fora da sessão do ICM.

## Conduzir: `/icm`

Um comando faz o ciclo curto: **painel → leitura → go do dono → despacho → gate de novo**.

| Quem | Decide o quê |
| --- | --- |
| Código (`conduzir`) | etapa atual (primeira não fechada), qual gate rodar, se falta handover, papéis candidatos da etapa, prontidão da issue, "próximo" |
| Jev | probabilidades: critério de aceite, escopo, bloqueio pendente (dado o estado das etapas) e, entre os candidatos, o papel mais adequado |
| Dono | go do despacho, papel final, dono de cada arquivo, gate humano |

- **Issue pronta** = critério de aceite e escopo claros e sem bloqueio pendente, todos fora da faixa incerta. Fora disso é `INCERTA` ou `REFINAR`, e a ação é refinar com o dono, nunca despachar.
- **Papel sugerido** é consultivo e restrito a `conducao.papeis_por_etapa`. Abaixo de `confianca_minima_papel`, ou com `nenhum`, fica sem sugestão e o dono escolhe. Isso mantém a D5 do handoff: o Jev não roteia o loop.
- **Despacho** é o argumento do `task` montado em código (`P.task`): contexto compartilhado, uma tarefa por issue, o corpo da issue por `gh issue view` (não é copiado), os caminhos citados que existem. Só sai com o go do dono e com um dono declarado por arquivo.
- O tracker é o GitHub Issues (D38). O condutor só lê (`gh issue list`); não cria nem fecha issue.
- Nada do painel é persistido: estado é derivado a cada chamada (A4). Recibos só entram no `jev.jsonl` por `registrar`.

## Comandos do `/icm`

`/icm [status|continue|duck|implement] [sprint | tema]`. Sem argumento é `status`, descrito acima.

| Modo | O que faz | Quem fecha |
| --- | --- | --- |
| `continue` | avança **um passo** da etapa atual (produzir handover, resolver achados do gate) e para no gate humano | dono |
| `duck` | conversa com o rubberduck, guarda o que vale em `docs/_backlog/` | dono posiciona (`git mv` para `01_grilling/inputs/` de sprint não iniciada) |
| `implement` | loop sobre todas as issues da sprint em `05_implement` | dono confere e fecha a etapa |

### Duck

- A prova vem do `11-discovery-rubberduck` (somente leitura). O item só é gravado por `docs/_index/icm-duck.mjs`, que **abre cada âncora `arquivo:linha` e exige o trecho na linha**; âncora que não bate bloqueia a gravação. Sem âncora, o item vale como ideia (`sem_ancora: true`).
- O Jev avalia o item (`pergunta_delimitada`, `afirma_sem_ancora`) e sugere um épico aberto, só acima de `confianca_minima_epico`. É consultivo.
- Estado derivado: o item em `_backlog/` está sem sprint; `sh docs/_index/estado.sh` lista. Ver `docs/_backlog/README.md`.

### Implementar

Fluxo: `plano` (read-only) → **go do dono** (`registrarGo`: papel e dono de caminhos por issue) → `passo` repetido → `fechar`.

- **Quais issues e em que ordem:** os `#N` citados em `04_tickets/handovers/tickets.md` (ou `issues` explícito); ordem topológica pelas `#N` da seção `Dependências` do corpo; critérios são os `- [ ]` da seção `Critérios de aceite`. Tudo extraído em código. Issue sem critério extraível, ciclo ou dependência aberta fora da sprint viram bloqueio, não palpite.
- **Uma iteração** (`passo`): mede o estado do git (hash dos arquivos) → despacha o papel (padrão `42-implementation-backend`, relatório estruturado) → mede de novo → roda a verificação (`mix test`) → pergunta ao Jev, por critério, se há execução observada que o cubra → grava em `05_implement/handovers/jev.jsonl`.
- **Veredito (código):** `ok` só com verificação em 0 e nenhum critério fora da faixa limpa. Teste falho ou critério sem prova → `reiterar`, com o feedback montado em código (critério, motivo, final da saída do teste) no prompt seguinte. Esgotadas as iterações (`max_iteracoes`) → `bloqueada`.
- **Bloqueada, sem negociação:** escrita fora do dono declarado, em caminho de `protegidos` (inclui `jev-gates.json`, `docs/_index/`, ADRs, canon), commit do subagente, `bloqueios` declarados por ele, verificador ausente, subagente ou juiz falhando. A issue e as que dependem dela param; as independentes seguem.
- **O que o loop nunca faz:** comitar, fechar issue, mudar `status:` de etapa, editar o que está protegido, trocar de ferramenta. Subagentes rodam em série, um dono por arquivo.
- **Retomada:** o progresso é derivado do `jev.jsonl`; `/icm implement` numa sessão nova continua da próxima issue.
- **Fechamento:** `fechar` gera `implementacao.md` a partir dos registros (recusa sobrescrever arquivo escrito à mão) e roda o gate `implementacao` sobre as issues `ok`. A verificação medida está na linha `verificação`; o texto dos critérios é declaração do subagente.

## Como o agente usa

1. **Antes de implementar:** `estado` e, se o ticket tiver mais de um caminho, `opcoes`. Consulta de código ao Jev não existe: ele não gera código nem escolhe ação.
2. **Antes de declarar uma etapa pronta:** o gate dela. Cada `ACHADO` e `INCERTO` é lido no artefato (`arquivo:linha`) e resolvido ou registrado, como em `docs/06_review/CONTEXT.md` passo 2. O veredito do Jev é evidência, não verdade.
3. **Ao entregar ao dono:** citar o `recibo` e o que foi confirmado por leitura. O fechamento continua sendo do dono (`docs/PROCESS.md`, regra de avanço).

## Restrições

Valem inteiras as de `_research/AlephBible/chat.md:457-466`. As que o código impõe:

- O Jev só responde sim/não atômico (`bool`); combinação, ranking, contagem, ordem de etapas, existência de arquivo e comparação de data são código.
- Nunca escreve `status:`, fecha etapa, gera texto de artefato nem escolhe a próxima ação.
- Falha de chave, rede, artefato ausente, padrão sem item ou truncamento produz `bloqueado` ou `TRUNCADO` visível, nunca veredito favorável nem fallback para outro modelo.
- Não alegar verificação não observada: o `texto` do gate imprime modelo, `calibrado` e recibo.

## Estado de calibração

`calibrado: false` em `jev-gates.json`. Os limiares (`faixa_incerta` 0,3–0,7) são a faixa genérica da doc do Jev, não medida neste domínio. Enquanto não houver pares `(veredito, decisão humana)` suficientes em `jev.jsonl`, o `ACHADO` é pista para ler, não para bloquear. O catálogo do omp só expõe `jev-latest`; pinar `jev-1.13.0` fica pendente até haver limiar calibrado (restrição 6 do handoff).

## Privacidade

O `state` sai da máquina para a TypeSafe. Handover do EnochDB carrega decisão de produto; é a questão A5 aberta do handoff (`chat.md:449`). Não passe segredo, credencial ou dado pessoal ao gate; o `07_handoff` já proíbe isso nos handovers.
