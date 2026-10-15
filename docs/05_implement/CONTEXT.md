# 05_implement — executar uma fatia

## Objetivo

Entregar o ticket autorizado sem ampliar seu escopo. Uma tarefa sem ticket ou autorização explícita não é entrada desta etapa.

## Entradas

- `04_tickets/handovers/tickets.md` e o corpo do ticket em curso.
- Mapeamento técnico de `03_spec`, se existir.
- [`../../CONTEXT.md`](../../CONTEXT.md), [`../canon.md`](../canon.md) e os ADRs relevantes em [`../adr/`](../adr/).

## Processo

1. Escolha um ticket cujos bloqueios estejam resolvidos e confirme seus critérios antes de editar.
2. Escreva o teste de comportamento primeiro quando houver seam apropriado; implemente só o necessário para passar.
3. Execute testes focados durante o trabalho e a suíte completa uma vez ao final.
4. Exercite o fluxo no programa real; teste isolado não substitui evidência ponta a ponta.
5. Registre ticket, commits, arquivos alterados, verificações observadas e pendências em `handovers/implementacao.md`.
6. Se surgirem novas decisões ou termos, atualize as fontes canônicas e sinalize qualquer mudança de escopo para aprovação.

## Saída e gate humano

Saída: `docs/_sprints/{sprint}/05_implement/handovers/implementacao.md`. O dono confere a evidência e pendências; não declare ticket ou etapa fechados sem o resultado correspondente.

Antes de pedir o gate, rode o gate `implementacao` ([`../agents/jev.md`](../agents/jev.md)): critério sem execução registrada é achado. Antes de começar, se houver mais de um caminho viável, use `opcoes`.
