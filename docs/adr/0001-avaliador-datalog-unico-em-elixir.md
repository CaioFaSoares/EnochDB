# ADR-0001 — O avaliador Datalog em Elixir é o único motor de consulta

- **Status:** proposta
- **Data:** 2026-10-15
- **Supera:** — (a D3 do grilling, só SQLite no e01, foi superada pela D7, e a D4, compilar Datalog para SQL, pela D6, ambas antes de virar ADR)

## Contexto

O Enoch precisa responder à mesma consulta Datalog sobre SQLite hoje e sobre MySQL e Postgres no e02. Compilar Datalog para SQL entrega a semântica ao banco: ordenação, comparação e plano de execução mudam a cada dialeto, e cada banco novo exige um compilador novo que pode responder diferente à mesma pergunta. O dono quer uma linguagem única que funcione com MySQL e Postgres com menos problemas.

A escolha também define o que o adaptador de storage precisa oferecer: um adaptador que compila consulta é outra fronteira que um adaptador que só devolve linhas.

## Decisão

- O avaliador em memória, escrito em Elixir, é o único motor de consulta. Joins, regras e semântica moram nele; a semântica é a mesma em qualquer banco.
- O adaptador oferece varreduras dos índices e pushdown mínimo: filtros por `a`, `v` e `t`, aplicados no banco antes de devolver as linhas. Não oferece `compile/2`.
- Os adaptadores `Memory` (ETS) e SQLite entram juntos no e01; o SQLite com `:memory:` segue disponível para testes que precisem de SQL real.
- Para bases passadas, a visibilidade dos datoms é resolvida no avaliador, em um só lugar (ver [ADR-0002](0002-modelo-acumulativo-log-estado-atual-historico.md)).
- As cláusulas do avaliador no e01 são as da D33 e a recursão fica no e02.

## Opções consideradas

- **Avaliador único em Elixir:** uma semântica, independente do banco; o custo é escrever o motor e o otimizador de joins.
- **Compilar Datalog para SQL (D4, rejeitada):** reaproveita o planner do SQLite, mas amarra a semântica ao dialeto de cada banco e exige um módulo de dialeto por banco.

## Consequências

- O módulo de dialeto por banco deixa de existir para consultas; `Enoch.Storage` passa a ser um contrato de varreduras.
- O planner do SQLite sai do caminho de consulta; o motor precisa de otimizador de joins próprio.
- Risco que o e02 herda: em banco de rede, cada varredura é uma ida e volta e traz linhas para o BEAM. No SQLite embutido isso quase não custa.
- Risco aceito pelo dono: a fronteira `Enoch.Storage` só é validada com duas implementações na s04 (D22). A mitigação, escrever na spec da s01 as consultas e os índices do SQLite para a varredura sem implementá-los, é iniciativa do agente, aceita junto com o conjunto no gate do `01_grilling`.

## Referências

- Decisões D6, D7, D8, D9, D10, D22, D33 em [`decisoes.md`](../_sprints/s01-nucleo-enoch/01_grilling/handovers/decisoes.md).
- Descrição do avaliador no chat original: [`../canon/chat.md`](../canon/chat.md) (linhas 153-182).
