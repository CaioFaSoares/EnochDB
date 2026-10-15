# ADR-0007 — Schema em dados, API funcional por nome de instância e registro por lista de módulos

- **Status:** aceita
- **Data:** 2026-10-15
- **Supera:** —

## Contexto

O desenho do chat original pede um banco por tenant criado em tempo de execução (`canon/chat.md:235`) e um `:memory:` por teste (`canon/chat.md:208`). Definir um módulo para cada banco não serve a nenhum dos dois. Uma macro que só atua na compilação também não serve a schemas que chegam como dados de qualquer lugar.

Além disso, uma extensão de domínio futura, como o ledger no e03, precisa compor schema, funções de transação e regras com o das aplicações sem colidir nomes, e o e02 vai desenhar o registro de extensões com os primeiros clientes reais (MySQL, Postgres, Absinthe, Ash).

## Decisão

- **Dados no centro, macro por cima.** A forma canônica do schema é uma lista de definições de atributo, em dados. A DSL `entity`/`attr` gera exatamente esses dados e valida referências em compilação; o instalador valida de novo. As opções já decididas viram campos: `scale`, `immutable`, `deprecated`, `unique`, `index`, `cardinality`. O instalador junta as listas de vários módulos e detecta colisão de nomes de atributo.
- **API funcional por nome de instância.** `Enoch.start_link(name: ..., adapter: ..., schema: [...])` e `Enoch.transact(nome, dados)`. `use Enoch.Repo` é uma camada fina que gera funções delegando ao núcleo. A API do e01 expõe `transact`, `q`, `pull`, `db`, `as_of` e `history`; `listen/1` é de eventos e fica no e02.
- **Registro por lista de módulos.** A instância recebe as listas nas opções (`schema:`, `functions:`, `rules:`). Funções de transação são pares `{nome, módulo}`, sendo o módulo o que implementa o behaviour; regras são definições com nome, argumentos e corpo. Os nomes têm espaço de nomes (`ledger/post`, `ledger/balance`) e o passo de registro recusa, com erro explícito, dois módulos que registrem o mesmo nome. Regras avulsas na própria consulta continuam permitidas.
- **Extensões no e01: só os pontos de extensão.** O behaviour `Enoch.Storage` e os metadados do schema legíveis por outros módulos. A suíte de contrato é um módulo reutilizável em `lib/` (por exemplo `use Enoch.Storage.ContractCase`). Registro e descoberta de extensões ficam para o e02.
- Cada instância sobe uma árvore de supervisão própria; o registro de extensões do e02 não pode ser impedido por esta API.

## Opções consideradas

- **Dados com macro como açúcar:** serve a instância em tempo de execução, a dados de qualquer origem e à detecção de colisão entre módulos.
- **Só macro/módulo por banco:** rejeitada; não cobre tenant em tempo de execução nem `:memory:` por teste sem um módulo para cada um.
- **Descoberta automática de extensões já no e01:** adiada para o e02, desenhada com os primeiros clientes.

## Consequências

- Uma extensão de domínio é uma lista de módulos de schema, uma de funções e uma de regras.
- Extensão interna é dependência opcional dentro do pacote `enoch`; externa é um pacote separado que implementa os mesmos behaviours. Os nomes de módulo não mudam entre as duas formas.
- Se o custo da s02 apertar, ela entrega primeiro os dados e o instalador, e a DSL no fim da sprint.
- O esqueleto do `Enoch.Repo` entra na s01 (D22, D32); o registro das funções, o passo do schema e as regras nomeadas chegam nas s02 e s03. Essa atribuição às sprints é iniciativa do agente (D34, D35), aceita junto com o conjunto no gate do `01_grilling`.

## Referências

- Decisões D24, D25, D31, D32, D35 e itens 29, 30, 33 em [`decisoes.md`](../_sprints/s01-nucleo-enoch/01_grilling/handovers/decisoes.md).
- Árvore de módulos: [`../arquitetura.md`](../arquitetura.md).
- Termos Aplicação e Extensão: [`../../CONTEXT.md`](../../CONTEXT.md).
