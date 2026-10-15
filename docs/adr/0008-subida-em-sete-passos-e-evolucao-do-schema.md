# ADR-0008 — Subida em sete passos e evolução do schema entre deploys

- **Status:** proposta
- **Data:** 2026-10-15
- **Supera:** — (a proposta original do item 35 do grilling foi corrigida pela D34 antes de virar ADR)

## Contexto

O dono quer que, ao subir, o sistema valide o que já existe, recupere o que for preciso ou construa sobre o que foi feito. A primeira proposta de sequência (item 35) se contradizia: o schema e as migrações gravam transações, mas o transactor só subia no passo 6, e as funções e regras eram registradas depois das migrações.

Deploys novos também mudam o schema, e o dono considera importante ter um caminho para migrar ou deprecar atributos antigos. O Datomic permite mudar um atributo gravando fatos novos, mas nunca o tipo (`docs.datomic.com/schema/schema-change.html`); o Tickety instala o schema em duas passadas por causa do índice antes do `unique`.

## Decisão

Sequência de subida do `Enoch.Repo` (D34):

1. Abrir o storage e conferir a versão do layout; recusar um layout mais novo que o conhecido.
2. Conferir que o estado atual e o log concordam e reconstruir o atual se divergirem; no `Memory`, aplicar a recuperação da [ADR-0003](0003-memory-ets-contador-base-e-recuperacao.md). Isso é feito pelo storage, antes de o transactor existir.
3. Iniciar o transactor com a admissão fechada a chamadores externos, aceitando só o caminho interno da subida.
4. Registrar funções de transação e regras.
5. Instalar o schema.
6. Aplicar as migrações de dados pendentes, cada uma uma só vez.
7. Abrir a admissão e emitir a telemetria da subida com a base.

Uma falha em qualquer passo impede a subida, com erro explícito, e a admissão continua fechada. A verificação de atributo materializado ([ADR-0010](0010-valor-derivado-nunca-e-fonte-de-verdade.md)) não é passo obrigatório. O Enoch não oferece gancho de subida para a aplicação; o padrão fica documentado no app de exemplo.

Regras do instalador (D29): atributo idêntico é no-op; atributo novo instala; alteração compatível aplica e é gravada como transação; alteração incompatível é erro explícito na subida, listando os conflitos (exemplos: mudar o tipo, mudar a `scale` de um `:decimal` com dados, remover `immutable`, tornar único com duplicatas atuais). A lista exata sai na spec. `deprecated: true` mantém o atributo legível e rejeita novas escritas, com aviso. Renomear muda o nome do mesmo atributo; o log guarda o id, então o histórico segue intacto. A migração de dados versionada (módulo que devolve dados de transação, aplicado uma vez, com o id gravado como fato único) entra na s05.

## Opções consideradas

- **Sequência corrigida (D34):** o transactor sobe antes do schema e das migrações, com a admissão fechada, e funções e regras estão registradas antes de serem usadas.
- **Sequência original do item 35:** rejeitada pela contradição acima.
- **Gancho de subida para a aplicação:** rejeitado; o núcleo oferece upsert idempotente (D14), metadados de transação (D11) e consultas, e o app de exemplo documenta o padrão.

## Consequências

- A subida precisa de um estado fechado da admissão, que a D27 não tinha.
- A versão do layout é método do contrato `Enoch.Storage` (iniciativa do agente, D34, aceita junto com o conjunto); o `Memory` é volátil e não persiste layout. A forma exata no SQLite (por exemplo `PRAGMA user_version`) não foi verificada e fica para a spec.
- A atribuição das entregas das D34 e D35 às sprints é iniciativa do agente, aceita junto com o conjunto no gate do `01_grilling`.
- Os geradores ficam fora do e01 e o app de exemplo da s05 prova a experiência (item 31). A tarefa de ensaio da instalação contra o banco atual segue o item 31 (D29), que só fechou a questão dos geradores; `decisoes.md` não diz se o ensaio entra no e01, e a spec decide.

## Referências

- Decisões D29, D34, D35 e itens 35, 37 em [`decisoes.md`](../_sprints/s01-nucleo-enoch/01_grilling/handovers/decisoes.md).
- Referências do Datomic: `docs.datomic.com/schema/schema-change.html`.
