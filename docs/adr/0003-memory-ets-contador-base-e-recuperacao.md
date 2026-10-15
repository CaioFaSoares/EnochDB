# ADR-0003 — `Memory` em ETS, com contador como base e recuperação do transactor

- **Status:** proposta
- **Data:** 2026-10-15
- **Supera:** — (a primeira versão da D16 para o `Memory`, estruturas persistentes, foi superada pela D18 antes de virar ADR)

## Contexto

No BEAM, uma estrutura persistente só compartilha memória dentro do heap de um processo; entregá-la a outro processo a copia, e `persistent_term` dispara coleta de lixo global a cada `put`. A primeira versão da D16 para o `Memory` contava com estruturas persistentes e um banco como valor barato; isso não se sustenta entre processos, e a própria D16 foi ressalvada nesse ponto.

Além disso, gravar uma transação no ETS não é atômico: são várias linhas e vários índices. Um leitor pode ver a escrita pela metade, e uma queda do transactor no meio deixa linhas órfãs com `tx = t+1`.

## Decisão

- Duas tabelas ETS: o histórico, `ordered_set` só com inserção, e o estado atual.
- O banco como valor é `{referências das tabelas, basis_t}`; criá-lo custa O(1) e a leitura copia só as linhas lidas.
- Um contador em `:atomics` **é** a base: vale `2t` com a base estável em `t` e `2t+1` enquanto a transação `t+1` escreve; o `basis_t` publicado é `div(contador, 2)`.
- Um leitor com base `b` só usa o estado atual se o contador valer `2b` antes e depois da varredura. Se a validação falhar, aquela varredura é refeita pelo histórico na mesma base, sem repetir em laço, então a consulta não sofre starvation sob escrita contínua e as demais cláusulas continuam coerentes.
- O contador nunca diminui, nem na recuperação.
- Recuperação após queda do transactor, antes de aceitar escrita: manter o contador em `2t+1`; apagar do histórico as linhas com `tx = t+1`; reconstruir o estado atual a partir do histórico até `t`; publicar `2(t+1)`. A transação `t+1` vira uma transação vazia e a próxima real é `t+2`: um `t` nunca é reutilizado.
- O processo dono das tabelas é separado do transactor e tem `heir`, para as tabelas sobreviverem à queda do transactor.

## Opções consideradas

- **ETS com contador-base (opção d2 do item 25):** presente rápido nos dois adaptadores; o preço é uma segunda tabela sincronizada e concorrência difícil de testar.
- **Estruturas persistentes no heap (D16, primeira versão):** rejeitada, porque copia ao passar de processo.
- **Seqlock simples sobre o estado atual:** rejeitado, porque só detecta escrita *durante* a varredura e não uma transação completa entre a captura do banco e a varredura.
- **Voltar o contador na recuperação (`2t+1` para `2t`):** rejeitado, porque reabre o ABA e um leitor aceitaria uma leitura rasgada.

## Consequências

- O custo do presente independe do histórico nos dois adaptadores, então o critério 3 da D17 vale para ambos.
- A suíte de contrato precisa incluir leitura concorrente com escrita e o teste "queda no meio da escrita", com leitor em curso, que também confere que o contador de admissão ([ADR-0004](0004-transactor-unico-regras-de-escrita-e-admissao.md)) volta a zero.
- Teste de contrato obrigatório (D18): um banco como valor de base antiga com uma transação completa entre a captura e a consulta. É o caso 2 do item 19, que a correção do contador fecha.
- A recuperação custa O(histórico) no reinício e deixa uma lacuna em `t`; aceitável porque o `Memory` é volátil.
- O `Memory` perde tudo ao reiniciar o nó e não serve de evidência de auditoria; a auditoria vive no log do SQLite.
- A spec precisa de provas de conceito: varredura de `ordered_set` com inserção concorrente, seqlock sob escrita contínua, recuperação e comportamento em `max_memory`.

## Referências

- Decisões D16, D18, D21 e itens 24, 25, 26 em [`decisoes.md`](../_sprints/s01-nucleo-enoch/01_grilling/handovers/decisoes.md).
- Modelo de dados que o `Memory` implementa: [ADR-0002](0002-modelo-acumulativo-log-estado-atual-historico.md).
