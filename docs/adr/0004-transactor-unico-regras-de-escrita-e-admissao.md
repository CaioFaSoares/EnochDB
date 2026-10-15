# ADR-0004 — O transactor único é dono das regras de escrita e da admissão

- **Status:** aceita
- **Data:** 2026-10-15
- **Supera:** —

## Contexto

Unicidade, imutabilidade e funções de transação são semântica. Se cada banco as impusesse, o mesmo problema da [ADR-0001](0001-avaliador-datalog-unico-em-elixir.md) voltaria: respostas diferentes por adaptador. Com mais de um transactor, ainda haveria uma janela entre a checagem de unicidade e a gravação.

Há também a dor da escrita em volume. O BEAM não tem caixa de entrada limitada; um laço infinito numa função de transação (`cas`, `post`) prenderia todas as escritas; e um chamador cuja transação deu timeout não sabe se ela foi aplicada.

## Decisão

- O transactor serializa todas as escritas e garante, para qualquer adaptador, a unicidade e o upsert por `unique: :identity`. O contrato do adaptador não tem mecanismo de unicidade; o SQLite pode manter um índice único parcial como rede de segurança, sem ser a fonte da regra (D14).
- `immutable: true` num atributo proíbe retraí-lo ou alterá-lo depois de afirmado, em todos os caminhos de escrita, inclusive um `transact` cru (D26).
- Funções de transação rodam em processo próprio com tempo e heap limitados; a morte do processo aborta só aquela transação e o transactor segue (D21).
- A admissão é um contador de admissão em `:atomics`, distinto do contador-base do `Memory` ([ADR-0003](0003-memory-ets-contador-base-e-recuperacao.md)): o chamador o incrementa antes de enviar a transação e o transactor o decrementa ao terminar. Acima do limite, o chamador é rejeitado antes de a mensagem entrar na caixa de entrada. O `init` do transactor zera o contador de admissão, porque a caixa nova nasce vazia; o contador-base nunca diminui.
- A admissão tem estado fechado e aberto: na subida ela aceita só o caminho interno (ver [ADR-0008](0008-subida-em-sete-passos-e-evolucao-do-schema.md)).
- Telemetria do tamanho da fila e das transações por segundo. A documentação diz que uma transação com timeout pode ter sido aplicada e que a defesa é uma chave de idempotência com `unique: :identity`.
- Group commit, `transact_async` com várias transações em andamento e pipeline ficam para depois de uma medição de vazão do `Memory` e do SQLite (s04 ou s05), sem mudar a API.

## Opções consideradas

- **Transactor único com as regras no motor:** uma semântica, sem janela entre checagem e gravação.
- **Unicidade pelo índice de cada banco:** rejeitada; a regra deixaria de ser única e dependeria do adaptador.
- **Filtrar no transactor ao receber a mensagem:** rejeitada; a mensagem já teria ocupado a caixa de entrada.
- **`GenServer` com `max_queue`:** não existe no BEAM.

## Consequências

- Escrita serializada, como no Datomic. O e02, com vários nós, precisa manter um único transactor por banco.
- Pendência para a spec: um chamador que morre entre incrementar e enviar vaza uma unidade do contador de admissão. A spec escolhe entre tratar esse caso e ler `Process.info(pid, :message_queue_len)`, que não vaza mas é uma checagem aproximada.
- [INFERÊNCIA] Dois pontos que `decisoes.md` não trata e a spec deve fechar: um chamador que incrementa antes de o `init` zerar e envia depois deixaria o contador negativo quando o transactor decrementar; e não está dito se um chamador rejeitado desfaz o próprio incremento.
- Quando o transactor cai, as mensagens da caixa morrem sem decrementar; o `init` zera o contador de admissão e o teste de contrato confere isso.
- A opção sem histórico por atributo (`noHistory` do Datomic) conflita com o log imutável da [ADR-0002](0002-modelo-acumulativo-log-estado-atual-historico.md) e precisa de decisão própria.
- A interação de `immutable` com a excisão (e02) e com a opção sem histórico fica para a spec.
- Direção do dono (2026-10-15) para uma divergência entre o índice único parcial do SQLite e o transactor: evitar que ocorra e, se ocorrer, valer o valor mais novo. [PROPOSTA do agente, a confirmar na spec] O índice nasce do schema, criado pelo instalador, e é gravado na mesma transação SQLite que o transactor confirma; o passo 2 da subida ([ADR-0008](0008-subida-em-sete-passos-e-evolucao-do-schema.md)) confere os dois; se o índice rejeitar o que o transactor aceitou, a transação inteira é revertida com erro explícito, sem gravação parcial. O que "mais novo" significa quando os dois discordam não está definido; para o estado atual contra o log, vale o log, que tem a transação mais recente.

## Referências

- Decisões D14, D21, D26, D27 e itens 27, 34 em [`decisoes.md`](../_sprints/s01-nucleo-enoch/01_grilling/handovers/decisoes.md).
- Documentação do Datomic citada no item 34: `transactions/transaction-processing.html` e `operation/capacity.html`.
