# ADR-0002 — Modelo acumulativo: log imutável, estado atual e índice de histórico

- **Status:** aceita
- **Data:** 2026-10-15
- **Supera:** — (a D15 do grilling, intervalo de visibilidade por linha, superou a D8; a D16 superou a D15 e restabeleceu a D8 para as bases passadas; a D28 revisou a D5 ao trazer o `:history` para o e01. Tudo antes de virar ADR)

## Contexto

O Enoch precisa de três coisas ao mesmo tempo: consulta ao presente cujo custo não cresce com o histórico, consulta a bases passadas (`as_of`, banco como valor antigo, `:history`) e um log completo que sirva de fonte de verdade e de auditoria.

A primeira tentativa (D15) guardava `added_tx` e `retracted_tx` em cada linha e retraía com `UPDATE`. Isso altera linhas existentes, desvia do modelo do Datomic e deixa o log, que deveria ser só de inserção, fora do caminho de consulta. O dono preferiu o modelo acumulativo do Datomic.

## Decisão

- Nenhuma linha de dados é atualizada no lugar. Retrair é gravar um datom novo com `added = false`.
- No SQLite, `datoms_log` é a fonte de verdade e o índice de histórico: só `INSERT`, protegido por gatilhos. Seus índices são covering, com `v` e `tx`: EAVT, AEVT, AVET (atributos indexados) e VAET (refs).
- `datoms` é o estado atual: projeção só com datoms vivos, reconstruível a partir do log e gravada na mesma transação SQL.
- A base escolhe o índice. `:current`, ou `basis_t` igual ao último `t`, lê o estado atual; no `Memory`, só enquanto o contador-base valer `2b` antes e depois da varredura ([ADR-0003](0003-memory-ets-contador-base-e-recuperacao.md)). `{:as_of, t}`, um banco como valor de base antiga e `:history` leem o histórico, onde o avaliador resolve a visibilidade: vale o último operador por `(e, a, v)` com `tx <= b`.
- `:history` entra no e01 (D28): é a base sem filtro de visibilidade, com afirmações e retrações. Entidade e `pull` sobre ela não fazem sentido; a spec define o comportamento.
- No SQLite, uma consulta usa uma transação de leitura numa só conexão, lê o último `t` dentro dela e o compara com a base; se a base é menor, lê o histórico.
- Direção do dono (2026-10-15): conferir esse `t` e, se divergir, ter uma forma de validar qual é o correto. [PROPOSTA do agente, a confirmar na spec] O `max(tx)` do `datoms_log` é o `t` autoritativo, porque o log é a fonte de verdade; se o estado atual ou um registro à parte discordar, o estado atual é reconstruído a partir do log (passo 2 da subida, [ADR-0008](0008-subida-em-sete-passos-e-evolucao-do-schema.md)).
- O critério de aceite é determinístico: o adaptador expõe as linhas lidas por varredura, e uma consulta ao presente lê o mesmo número delas antes e depois de N retrações (D17, critério 3). A métrica determinística, em vez de tempo, é iniciativa do agente, aceita junto com o conjunto no gate do `01_grilling`.

## Opções consideradas

- **Modelo acumulativo, estilo Datomic:** log imutável mais estado atual e histórico; o presente depende do presente, e o log é só inserção.
- **Linhas com intervalo de visibilidade (D15, rejeitada):** o predicado de visibilidade ficaria no adaptador, mas exige `UPDATE` para retrair e mantém o log fora da consulta. A D16 restabeleceu a regra da D8, com a visibilidade do passado resolvida no avaliador e o presente lido do estado atual.

## Consequências

- O presente cresce com o tamanho do presente; o passado custa o histórico do padrão pedido.
- Cada escrita grava o log (com seus índices) e o estado atual. Custo aceito pelo dono.
- O estado atual é derivado: o critério 4 da D17 exige que o reconstruído a partir do log seja idêntico ao gravado.
- O predicado de visibilidade existe uma vez, no avaliador, e a suíte de contrato o cobre nos dois adaptadores.
- A forma de `Memory` é decidida na [ADR-0003](0003-memory-ets-contador-base-e-recuperacao.md); a D16 não promete banco como valor grátis entre processos.

## Referências

- Decisões D8, D15, D16, D17, D28 e itens 19, 21, 22, 23 em [`decisoes.md`](../_sprints/s01-nucleo-enoch/01_grilling/handovers/decisoes.md).
- Modelo de índices do Datomic: `https://docs.datomic.com/indexes/index-model.html` e `https://docs.datomic.com/reference/filters.html`.
- Gatilhos e índices no chat original: [`../canon/chat.md`](../canon/chat.md) (linhas 47-48 e 390-396).
