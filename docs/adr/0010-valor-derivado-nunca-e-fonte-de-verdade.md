# ADR-0010 — Valor derivado nunca é fonte de verdade

- **Status:** proposta
- **Data:** 2026-10-15
- **Supera:** — (revoga em parte a D30: a opção C, que a D30 mandava para o e02, entra no e01 por decisão do dono em 2026-10-15)

## Contexto

O dono quer levar saldos e outros valores derivados para perto do núcleo, e o e03 depende de somas e saldos (D9). Materializar um valor cria o risco de ele divergir dos fatos que o originam e de virar uma segunda fonte de verdade ao lado do log; sem uma regra explícita, a primeira otimização de saldo a introduziria. No Tickety nada é materializado: o saldo é derivado por consulta (ADR-0003 do Tickety, citada em `db/payments.clj` e `db/history.clj`). O chat original soma o saldo a cada consulta e só o promove a projeção mantida pelo transactor quando ficar lento, sempre reconstruível a partir do log (`canon/chat.md:404-406`).

## Decisão

- Regra do projeto: um valor derivado nunca é fonte de verdade; precisa ser reconstruível a partir do log e verificável contra o recálculo.
- O e01 entrega a leitura por regras nomeadas e agregados (opção A), correta em qualquer `as_of`, sem armazenamento extra.
- O e01 entrega também a verificação de um atributo materializado contra uma regra: `Enoch.verify_derived` compara o valor gravado com o recálculo e aponta as divergências. É uma opção de subida, desligada por padrão ([ADR-0008](0008-subida-em-sete-passos-e-evolucao-do-schema.md)).
- A manutenção automática de atributo derivado declarado no schema (opção C) entra no e01 (dono, 2026-10-15), no lugar do e02 da D30: o schema declara o atributo e a regra que o deriva, o motor escreve o valor na mesma transação, e `Enoch.verify_derived` e a reconstrução a partir do log seguem disponíveis. A sprint que a entrega fica para a `03_spec`; a opção C depende do schema (s02) e das regras nomeadas (s03).
- Os assinantes de eventos (opção D) ficam para o e02, desenhados com o ledger.

## Opções consideradas

- **A, leitura por regras e agregados, mais a verificação:** custo proporcional aos fatos envolvidos; a verificação é a primitiva de que a opção C precisa.
- **B, função de transação que também grava o valor derivado:** consistente com o `as_of` e com leitura O(1), com risco de divergência se a função tiver um erro.
- **C, atributo derivado declarado no schema e mantido pelo motor:** escolhida para o e01 pelo dono, revogando em parte a D30. A manutenção incremental é difícil, porque recalcular as entidades afetadas custa o tamanho dos fatos delas e só agregados simples admitem atualização por delta; a spec decide o corte entre os dois.
- **D, assinante de eventos:** eventualmente consistente; fica no e02.

## Consequências

- A entrega de C no e01 amplia o escopo da D22; a sprint e o corte (agregados simples por delta, recálculo para o resto) saem na spec. Em aberto, o dono não respondeu: se `verify_derived` passa a ser obrigatório na subida quando houver atributo derivado.
- A verificação depende das regras nomeadas da s03, e por isso chega com elas.

## Referências

- Decisões D9, D10, D30 e item 38 em [`decisoes.md`](../_sprints/s01-nucleo-enoch/01_grilling/handovers/decisoes.md).
- Regras nomeadas: [ADR-0007](0007-schema-em-dados-api-funcional-e-registro-por-modulos.md).
