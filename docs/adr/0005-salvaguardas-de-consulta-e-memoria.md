# ADR-0005 — Consulta abusiva morre e a memória do `Memory` tem limite explícito

- **Status:** proposta
- **Data:** 2026-10-15
- **Supera:** —

## Contexto

O `Memory` guarda tudo em ETS e roda dentro da VM da aplicação. O scheduler do BEAM preempta por reduções, então uma consulta longa não trava o nó; o risco real é memória, e o ETS não conta para o `max_heap_size`. Uma consulta abusiva ou uma escrita sem limite pode consumir o servidor.

O dono escolheu, entre matar a consulta abusiva e proteger o servidor de outro modo, **matar a consulta**, e pediu um sistema de salvaguardas, não só um limite numérico.

## Decisão

- Cada consulta roda num processo próprio, com `max_heap_size` e tempo limite. Ao estourar, morre só esse processo e o chamador recebe um erro explícito que diz qual limite estourou. Uma consulta só lê e não deixa estado; a próxima chamada pega um banco como valor novo (D19).
- `max_memory` é obrigatório no `Memory`: sem ele o adaptador não sobe, com erro claro (D20). `:infinity` é permitido, mas explícito, e a subida registra um aviso de que só o sistema operacional protege a máquina (item 28, confirmado na D21).
- Antes de gravar, o transactor confere `:ets.info(tabela, :memory)` das duas tabelas. Acima de `max_memory`, rejeita a transação com erro explícito; as leituras continuam funcionando.
- O limite brando, um percentual de `max_memory` cujo valor a spec decide, emite um alerta antes de a escrita ser rejeitada. Entra no e01 (D21).
- Telemetria: memória usada, consultas mortas por limite, transações rejeitadas por cota e linhas lidas por varredura (a métrica do critério 3 da D17).
- Os limites das funções de transação estão na [ADR-0004](0004-transactor-unico-regras-de-escrita-e-admissao.md); a supervisão e a recuperação, na [ADR-0003](0003-memory-ets-contador-base-e-recuperacao.md).

## Opções consideradas

- **Matar a consulta e rejeitar a escrita acima do limite, com erro explícito:** o sistema segue pronto para a próxima chamada.
- **Proteger o servidor em vez de matar a consulta:** rejeitada pelo dono (D19).
- **`max_memory` opcional:** rejeitado; sem limite declarado o `Memory` não sobe (D20).

## Consequências

- Um limite estourado é um erro com causa nomeada, como o estouro de 64 bits do `:decimal`.
- O limite brando precisa de um valor, que fica para a spec.
- A proteção contra o sistema operacional matar a VM inteira é o limite de memória do contêiner ou do sistema, fora do Enoch.
- A spec precisa de uma prova de conceito do comportamento ao atingir `max_memory`.

## Referências

- Decisões D19, D20, D21 e itens 26, 28 em [`decisoes.md`](../_sprints/s01-nucleo-enoch/01_grilling/handovers/decisoes.md).
