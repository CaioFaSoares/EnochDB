# 04_tickets — planejar fatias

## Objetivo

Dividir a spec em entregas pequenas, verticais e demonstráveis, com bloqueios que representem dependências reais.

## Entradas

- `03_spec/handovers/spec.md` e, se existir, `spec-tecnica.md`.
- Glossário e ADRs locais.
- Contrato do tracker em [`../agents/README.md`](../agents/README.md).

## Processo

1. Proponha uma fatia por caminho completo de comportamento, não uma camada horizontal isolada.
2. Para cada dependência, confirme que o ticket bloqueador é necessário para começar a fatia; evite serializar trabalho paralelo.
3. Para migração ampla, ordene expansão, migração por lotes e remoção da forma antiga em fatias separadas.
4. Apresente títulos, escopo, critérios de aceite e arestas para aprovação humana antes de publicar.
5. Publique no tracker definido em `../agents/README.md` somente depois da aprovação humana do passo 4; antes disso a proposta fica em `handovers/tickets.md`.

## Saída e gate humano

Saída: `docs/_sprints/{sprint}/04_tickets/handovers/tickets.md`. O dono aprova granularidade e bloqueios. A etapa só fecha após publicar ou registrar explicitamente que o trabalho é uma passada única e foi marcado `nao-aplicavel` segundo as regras do processo.

## Quando não se aplica

Pode ser `nao-aplicavel` para uma tarefa isolada que não possa ser dividida sem custo maior que o trabalho. A ficha explica a razão e registra o risco de não haver trilha por ticket.
