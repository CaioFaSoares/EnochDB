# Decisões do 01_grilling — s01-nucleo-enoch

Estado (2026-10-15): **sem pontos abertos; o dono aceitou o conjunto em 2026-10-15** (gate do `01_grilling`, `../../../../01_grilling/CONTEXT.md`, ficha `fechado`). Fontes lidas: [`../../../../canon.md`](../../../../canon.md), [`../../../../canon/chat.md`](../../../../canon/chat.md), [`../../../../../CONTEXT.md`](../../../../../CONTEXT.md).

**Iniciativas do agente que o dono ainda não confirmou explicitamente** (o aceite do conjunto as confirma; qualquer uma pode ser vetada):
- D17, critério 3: o gate é o contador de linhas lidas, não tempo.
- D22: a mitigação de escrever no papel as consultas e os índices do SQLite na spec da s01, e a atribuição das entregas de D34 e D35 às sprints.
- D23: o piso `~> 1.20` em `mix.exs`.
- D33: o `not` simples no avaliador, por ser o mesmo mecanismo do `not-join`.
- D36: igualdade e junção entre tipos não numéricos diferentes não casam, sem erro.
- D38: os usos práticos do flake (`nix run .#test` e afins) e o `Dockerfile` em dois estágios.
- Datas: os documentos usam 2026-10-13 e 2026-10-14 nas decisões anteriores; a data da máquina é 2026-10-15.

## Decisões fechadas

**D1. Divisão em três épicos (dono, 2026-10-13).**
- `e01-nucleo-enoch`: o Enoch como biblioteca embutível. Núcleo transacional, schema em Elixir, pull e Datalog básico. Os demais itens do e01 estão em D5 e D6.
- `e02-adaptadores-e-integracoes`: MySQL, Postgres, Absinthe, Ash, Litestream, corrente de hashes, excisão, regras recursivas e ~~agregados~~. ↳ [Atualizado — 2026-10-13 · D9]: os agregados foram para o e01.
- `e03-obol-sobre-enoch`: refazer o Obol sobre o Enoch como banco, API e backend de ledger.

**D2. O primeiro cliente real é o Obol, não o `Thoth` do chat (dono, 2026-10-13).** O Obol já existe em `_Mine/Obol`. A reescrita só começa quando o Enoch estiver pronto (e03).

**D5. Itens do chat que não tinham casa (dono, 2026-10-13).**
- No e01: tempids, lookup refs, funções de transação (`cas`) e `as_of`.
- No e02: ~~histórico completo (`:history`) e~~ eventos de transação (PubSub). ↳ [Atualizado — 2026-10-14 · D28]: o `:history` passou para o e01.
- Aceita antes de os metadados de transação e do tipo `:decimal` serem listados; ver item 11 das abertas.

**D6. O avaliador Datalog em memória, escrito em Elixir, é o único motor de consulta; o compilador de Datalog para SQL é descartado (dono, 2026-10-13).** Motivo dado pelo dono: uma linguagem única, que funcione com MySQL e Postgres no futuro com menos problemas. Isso **supera a D4**, que escolhera o compilador para SQL (`../../../../canon/chat.md:153-178`). O avaliador é descrito em `../../../../canon/chat.md:180-182`.

Consequências registradas, não ainda decididas em separado:
- A semântica do Datalog passa a ser do motor, igual em qualquer banco. O módulo de dialeto por banco de `canon/chat.md:323` deixa de existir para consultas.
- O adaptador deixa de oferecer `compile/2` e passa a oferecer varreduras dos índices. Isso muda a fronteira `Enoch.Storage` (item 3).
- O planner do SQLite sai do caminho de consulta; o motor precisa de um otimizador de joins próprio.
- **Risco de desempenho em banco de rede.** A semântica única reduz problemas de dialeto, mas não de desempenho. Com MySQL e Postgres, cada varredura é uma ida e volta pela rede e traz linhas para o BEAM. No SQLite embutido isso quase não custa. É o risco que o e02 herda.

**D7. Fronteira `Enoch.Storage` no e01 (dono, 2026-10-13).**
- O adaptador oferece varreduras dos índices e aceita pushdown mínimo: filtros por `a`, `v` e `t`, aplicados no banco antes de devolver as linhas. Joins, regras e semântica ficam no avaliador.
- O adaptador `Memory` (ETS) entra no e01, junto com o SQLite. O SQLite com `:memory:` continua disponível nos testes que precisem de SQL real.
- Supera D3.
↳ [Atualizado — 2026-10-13 · D15, mantido em D16]: o filtro por `t` do pushdown vira a base `basis_t` do `db`, que escolhe entre o índice atual e o de histórico.
↳ [Atualizado — 2026-10-13 · D16, corrigido em D18]: o `Memory` usa ETS para o histórico e para o estado atual (ver D18).

**D8. A visibilidade do `as_of` é resolvida no avaliador, não nos adaptadores (dono, 2026-10-13).**
- Para `{:as_of, t}`, o adaptador devolve as linhas de afirmação e retração do padrão pedido com `tx <= t` (o pushdown de `t` da D7). O avaliador resolve a visibilidade em um só lugar: vale o último operador por `(e, a, v)`.
- Para `:current`, a varredura lê a tabela `datoms` e não há retrações a resolver.
- Custo aceito: trafegar as linhas retraídas do padrão pedido. Pouco no SQLite embutido; pesa em banco de rede (e02).
- A regra de visibilidade existe uma vez, no motor. Isso preserva o motivo da D6.
↳ [Superada em D15 e restabelecida em D16 — 2026-10-13]: para bases passadas (`as_of`, `db` antigo, `history`) o avaliador volta a resolver a visibilidade, em um só lugar. Para o presente a varredura lê o índice atual e não há retrações a resolver.

**D9. Agregados no e01; regras recursivas no e02 (dono, 2026-10-13).**
- Agregados (`count`, `sum`, `min`, `max`) são recurso do avaliador e entram no e01. O e03 depende de somas e saldos.
- Regras recursivas (avaliação semi-naive, estratificação, terminação) ficam no e02, como em D1.
- Regras nomeadas não recursivas: ver D10.

**D10. Regras nomeadas não recursivas no e01 (dono, 2026-10-13).** São expansão de cláusulas no avaliador. A recursão continua no e02 (D9).

**D11. Metadados de transação e tipo `:decimal` no e01 (dono, 2026-10-13).**
- Metadados de transação (`tx/user`, `tx/reason`, `tx/source`): atributos na entidade de transação (`canon/chat.md:377`).
- Tipo `:decimal` na DSL de schema (`canon/chat.md:360`).
- A codificação do `:decimal` ainda não está decidida; ver item 16.

**D12. Codificação do `:decimal` (dono, 2026-10-13).**
- Inteiro escalado, com a escala fixa por atributo e declarada no schema. Exemplo: `attr :amount, :decimal, scale: 2` grava `1050` para `10,50`. Preserva a ordem, então o pushdown de `v` da D7 continua válido, e os agregados da D9 somam inteiros.
- O inteiro tem 64 bits (limite do SQLite). Estouro é erro explícito, nunca truncamento.
- O tipo `:decimal` não conhece moeda. A moeda é domínio do ledger e fica para o e03, como extensão ao núcleo do Enoch (ver `../../../../epicos/e03-obol-sobre-enoch.md`).
- A normalização dos valores de entrada para a escala do atributo está em D13.

**D13. Normalização do `:decimal` (dono, 2026-10-13).** Um valor com mais casas que a escala do atributo é rejeitado com erro explícito; não há arredondamento no framework. Um valor com menos casas é aceito e normalizado para a escala (`1,5` em escala 2 vira `1,50`), porque não perde informação. A regra de arredondamento fica na aplicação.

**D14. O transactor garante a unicidade para todos os adaptadores (dono, 2026-10-13).** A semântica de `:db.unique` e do upsert por `unique: :identity` mora no motor, como em D6. O contrato do adaptador não inclui um mecanismo de unicidade. O SQLite pode manter o índice único parcial como rede de segurança, sem ser a fonte da regra. Invariante a preservar: um único transactor serializa as escritas, o que evita a janela entre a checagem e a gravação; o e02 precisa mantê-lo com vários nós (`canon/chat.md:325-330`).

**D15. Linhas com intervalo de visibilidade (dono, 2026-10-13).**
- Cada datom guarda `added_tx` e `retracted_tx` (nulo enquanto vale). Retrair marca a linha, não a apaga. A chave da tabela inclui `added_tx`, para o mesmo `(e, a, v)` poder ser reafirmado depois de uma retração.
- Um datom é visível na base `b` se `added_tx <= b` e (`retracted_tx` é nulo ou `retracted_tx > b`). O contrato do adaptador define isso uma vez, e o predicado precisa estar na suíte de contrato dos dois adaptadores.
- Todas as varreduras de uma consulta recebem o mesmo `basis_t` do `db`. Isso cobre os três casos do item 19 sem depender de conexão fixa nem de leitura pelo log.
- O log imutável continua como registro de auditoria e para a hash chain do e02; fica fora do caminho de consulta.
- Supera a D8: a visibilidade deixa de ser resolvida no avaliador e vira um predicado do adaptador. O motivo da D6 se preserva porque o predicado é único e testado. O custo que a D8 aceitou (trafegar linhas retraídas) desaparece, porque o filtro roda no banco.
- O caminho rápido para o presente está no item 21.
↳ [Superada — 2026-10-13 · D16]: o intervalo `added_tx`/`retracted_tx` é abandonado a favor do modelo acumulativo do Datomic.

**D16. Modelo acumulativo, estilo Datomic: log imutável, índice atual e índice de histórico (dono, 2026-10-13).** Fonte da referência: `https://docs.datomic.com/indexes/index-model.html` (seção "Implementation") e `https://docs.datomic.com/reference/filters.html`.
- Nenhuma linha de dados é atualizada no lugar. Retrair é gravar um datom novo com `added = false`. A D15 gravava `retracted_tx` com UPDATE, o que era desvio do Datomic.
- **SQLite.** `datoms_log` é a fonte de verdade e o índice de histórico: só INSERT, protegido pelos gatilhos de `canon/chat.md:390-396`. Seus índices precisam ser covering, com `v` e `tx`: EAVT, AEVT, AVET (atributos indexados) e VAET (refs). O chat define `log_eavt(e, a, tx)` e `log_aevt(a, e, tx)` sem `v` (`canon/chat.md:47-48`), o que não basta. `datoms` é o estado atual: projeção só com datoms vivos, reconstruível a partir do log e gravada na mesma transação SQL (`canon/chat.md:126`). Sem colunas `added_tx` e `retracted_tx`.
- ~~**`Memory`.** O `db` guarda estruturas persistentes imutáveis, uma para o índice atual e uma para o de histórico.~~ ↳ [Superado — 2026-10-13 · D18]: o `Memory` usa tabelas ETS, não estruturas persistentes no heap de um processo.
- **Escolha do índice pela base.** `:current`, ou `basis_t` igual ao último `t`, lê o índice atual, sem custo de histórico. `{:as_of, t}`, `db` antigo e `:history` leem o índice de histórico. No histórico, a regra de visibilidade (vale o último operador por `(e, a, v)` com `tx <= b`) é resolvida no avaliador (D8 restabelecida); as linhas de um mesmo `(e, a, v)` chegam adjacentes e ordenadas por `tx`.
- **Custos aceitos pelo dono.** O presente cresce com o tamanho do presente, não com o histórico. O passado custa o histórico do padrão pedido. Cada escrita grava o log (com os índices dele) e o estado atual, como o Datomic grava log e índices.
- Supera a D15. Fecha os itens 19, 21 e 22. Detalhes que dependem da spec: itens 23 e 24.
↳ [Ressalva — 2026-10-13]: o compartilhamento estrutural do `Memory` só existe dentro do heap de um processo no BEAM; passá-lo a outro processo copia. Ver item 25. A D16 não promete snapshot grátis entre processos.

**D17. Critério de aceite do e01 (dono, 2026-10-13).** O e01 só fecha com os quatro itens abaixo:
1. Uma suíte de contrato única, rodando nos dois adaptadores (SQLite e `Memory`), cobrindo visibilidade, `as_of`, unicidade, ordem e normalização do `:decimal`, tempids e lookup refs.
2. Um app de exemplo que declara um schema com `:decimal`, faz `transact` com tempids, lookup refs, `cas` e metadados de transação, e consulta com `q` (agregado e regra não recursiva), `pull` e `as_of`.
3. O custo do presente não depende do histórico, nos dois adaptadores (D18). O gate é determinístico: o adaptador expõe o número de linhas lidas por varredura (contador ou telemetria), e o teste afirma que uma consulta ao presente lê o mesmo número de linhas antes e depois de N retrações do atributo. Um benchmark de tempo é complemento, não gate. (O dono aprovou "medido"; a métrica determinística é refinamento do agente, a partir da revisão.)
4. Persistência: um banco SQLite em arquivo sobrevive a reinício, e o estado atual reconstruído a partir do log é idêntico ao gravado.

**D18. O `Memory` usa ETS com histórico e estado atual, protegido por um seqlock (dono, 2026-10-13).** É a opção d2 do item 25.
- Uma tabela ETS `ordered_set` de histórico, só com inserção. Uma tabela ETS separada com o estado atual.
- O `db` é `{refs das tabelas, basis_t}`: `db()` custa O(1) e a leitura copia só as linhas lidas.
- Histórico: filtrar `tx <= basis_t` dá consistência, porque nada é alterado no lugar.
- Presente: um seqlock em `:atomics`. O transactor incrementa o contador antes e depois de escrever. O leitor confere que o contador está par e não mudou. **Sem retry em loop** (esclarecimento de 2026-10-13, vindo da revisão): na primeira validação que falhar, aquela varredura é refeita pelo histórico na mesma `basis_t` do `db`. A consulta nunca recomeça, não sofre starvation sob escrita contínua e continua consistente com as outras cláusulas, que usam o mesmo `b`. É a regra do item 23, com o seqlock no lugar do snapshot do WAL.
- ↳ [Corrigido — 2026-10-13, vindo da revisão]: o seqlock acima só detecta escrita **durante** a varredura. Ele não detecta uma transação completa entre a captura do `db` e o início da varredura: o `db` de `b = L` leria a tabela atual já em `L+1` (o caso 2 do item 19 voltaria no `Memory`). Regra corrigida: o contador **é** a base. Vale `2t` quando estável em `t` e `2t+1` enquanto a transação `t+1` escreve. O `basis_t` publicado é `div(contador, 2)`, lido do mesmo `:atomics`. Um leitor com `db` de base `b` só usa a tabela atual se o contador valer `2b` antes e depois da varredura; em qualquer outro caso lê o histórico em `b`. O contador só cresce, então não há ABA. Ordem do escritor: contador para `2t+1`; inserir no histórico; atualizar o atual; contador para `2t+2`. Teste de contrato obrigatório: `db` antigo com uma transação completa entre a captura e a consulta.
- ↳ [Regra do contador — 2026-10-13, vinda da revisão]: o contador nunca diminui, nem na recuperação do escritor (ver D21 e item 26).
- Consequência: o presente é rápido nos dois adaptadores, então o gate do critério 3 da D17 vale para ambos.
- Preço aceito: uma segunda tabela sincronizada com o histórico, lógica de repetição e concorrência difícil de testar. A suíte de contrato precisa incluir um teste de leitura concorrente com escrita.
- Fecha os itens 24 e 25. As salvaguardas de memória estão no item 26.

**D19. Consulta abusiva é morta, e o sistema segue pronto para a próxima (dono, 2026-10-13).**
- Cada consulta roda num processo próprio com `max_heap_size` e tempo limite. Ao estourar, morre só esse processo, e o chamador recebe um erro explícito que diz qual limite foi estourado. Entre matar a consulta abusiva e proteger o servidor, o dono escolheu **matar a consulta**.
- Uma consulta só lê e não deixa estado. A próxima chamada pega um `db()` novo e lê o estado atual.
- Interpretação do agente da frase do dono ("uma relida no estado atual para voltar"): quando a queda atinge o **escritor**, o sistema volta por uma releitura do estado atual, a partir do histórico. A regra concreta está no item 26 e aguarda confirmação.

**D20. `max_memory` é obrigatório; `:infinity` é permitido, mas explícito (dono, 2026-10-13).** Se faltar na configuração, o `Memory` não sobe e dá erro claro. O dono quer que isso seja parte de um **sistema de salvaguardas**, e não apenas um limite numérico; o desenho do sistema está no item 28.

**D21. Sistema de salvaguardas do `Memory` (dono, 2026-10-13).** O dono confirmou os itens 27 e 28 e a recuperação do item 26, com o ajuste da D18 (o `basis_t` deriva do contador).
- Limite duro `max_memory` (D20) e limite brando, que emite um alerta antes de a escrita ser rejeitada; o limite brando entra no e01. O percentual é decidido na spec.
- Limites de consulta (D19) e funções de transação em processo próprio, com tempo e heap limitados; a morte aborta só aquela transação e o transactor continua.
- Supervisão: processo dono das tabelas separado do transactor, com `heir`.
- Recuperação do escritor, corrigida em 2026-10-13: o contador nunca volta. Fica em `2t+1` durante a limpeza, as linhas órfãs `tx = t+1` são apagadas, a tabela atual é reconstruída a partir do histórico até `t`, e o contador é publicado em `2(t+1)`. O `t+1` vira uma transação vazia, e a próxima transação real é `t+2`.
- Telemetria: memória usada, consultas mortas por limite, transações rejeitadas por cota e linhas lidas por varredura.

**D22. O e01 tem cinco sprints, em camadas (dono, 2026-10-13).**
- **s01:** contrato `Enoch.Storage` e adaptador `Memory` (ETS com histórico e atual, contador-base, recuperação do escritor); transactor com `add` e `retract` crus; árvore de supervisão e esqueleto do `Enoch.Repo`; suíte de contrato inicial e contador de linhas lidas. Decisões cobertas: D7, D16, D18, D21 (recuperação e supervisão).
- **s02:** schema DSL, bootstrap, registro e instalação aditiva; tipos, cardinalidade e `:decimal`; unicidade e upsert, tempids, lookup refs, funções de transação e metadados de transação. Cobre D5, D11, D12, D13, D14.
- **s03:** avaliador Datalog (cláusulas, joins, predicados, agregados, regras não recursivas), `pull`, `as_of` com resolução de visibilidade no histórico, limites de consulta. Cobre D6, D8, D9, D10, D16, D19.
- **s04:** adaptador SQLite (log imutável com gatilhos, índices covering de histórico, estado atual, regra do item 23, persistência e reconstrução); a suíte de contrato passa nos dois adaptadores. Cobre D16 e D17 (critérios 1, 3 e 4).
- **s05:** salvaguardas restantes (`max_memory`, limite brando, funções de transação limitadas, telemetria), app de exemplo e fechamento da D17 (critério 2). Cobre D19, D20, D21.
- Risco aceito pelo dono: a fronteira `Enoch.Storage` é validada com duas implementações só na s04. Mitigação proposta pelo agente, sem custo de sprint: a spec da s01 escreve no papel as consultas e os índices do SQLite para o contrato de varredura (item 23), sem implementá-los. O dono não confirmou essa mitigação.
- A s01 testa `add` e `retract` crus. A retração implícita de cardinalidade um depende do schema e fica na s02.
↳ [Atualizado — 2026-10-14 · D28]: a s03 também entrega a base `:history`.
↳ [Atualizado — 2026-10-14 · D29 e D30]: a s02 inclui as regras do instalador, `deprecated` e renomear; a s05 inclui a migração de dados versionada; a verificação de atributo materializado vem com as regras da s03.
↳ [Atualizado — 2026-10-14 · D33]: a s02 também inclui `:db/retractEntity` simples; a s03 também inclui as cláusulas do avaliador listadas na D33, o `txInstant` consultável, o `as_of` por data e o invólucro público do `scan`.
↳ [Atualizado — 2026-10-14 · D34 e D35]: atribuição das entregas novas às sprints, proposta do agente e não confirmada pelo dono. s01: o esqueleto da sequência de subida (passos 1, 2, 3 e 7), a versão do layout como método do contrato `Enoch.Storage` (o `Memory` é volátil e não persiste layout), o estado fechado e aberto da admissão no transactor (a D27 não tinha estado fechado) e o registro de funções e regras como mecanismo, sem conteúdo. s02: registro das funções de transação (D35) e o passo do schema. s03: registro das regras nomeadas (D35), `Enoch.verify_derived` e a opção de subida que o chama, desligada por padrão (D30, D34). s04: a versão do layout gravada e conferida no SQLite. s05: as migrações pendentes na subida (D29), os limites e a telemetria.

**D23. Pacote único, `exqlite`, toolchain atual e foco em prova de conceito (dono, 2026-10-13).**
- Um único pacote `enoch`, com a aplicação OTP `:enoch` e os módulos sob `Enoch`. Nada de vários pacotes no e01. Os adaptadores seguem como módulos (`Enoch.Adapters.SQLite`, `Enoch.Adapters.Memory`).
- Driver SQLite: `exqlite`.
- Versões: a mais recente estável do Elixir que funcione com tudo isso. Verificado em 2026-10-14: a última release estável do Elixir é a v1.20.4 (`github.com/elixir-lang/elixir/releases/tag/v1.20.4`, `prerelease: false`, publicada em 2026-08-28). Com Elixir 1.20.4 e OTP 29.1.1 (Homebrew), o `exqlite` 0.42.0 compila e roda um teste de fumaça com `PRAGMA journal_mode = WAL`, tabela `STRICT, WITHOUT ROWID` com coluna `ANY` e índice parcial. O SQLite embutido do `exqlite` ali é o 3.53.4, não o 3.54.0 do sistema. O alvo é Elixir 1.20.4 com OTP 29. Não testado: OTP 28 e Linux.
- O piso declarado em `mix.exs` acompanha o alvo (`~> 1.20`), salvo se o dono pedir um piso menor. Essa escolha é do agente, não do dono.
- Nome: `enoch`, `enoch_db` e `enochdb` retornam HTTP 404 em `hex.pm/api/packages/<nome>` em 2026-10-14, ou seja, estão livres. O pacote ainda não foi publicado.
- O Obol não entra no e01 nem no e02. O dono quer o banco pronto para provar o conceito. O e03 (D2) continua sendo o lugar do Obol.
- Fatos verificados em 2026-10-14, completados em 2026-10-15. (1) O SQLite do Enoch é o embutido no `exqlite` (3.53.4 no teste): a versão fica presa à do `exqlite`, e o `sqlite3` do sistema serve só de CLI. (2) A release `v0.42.0` do `exqlite` publica NIFs pré-compilados **por versão de NIF**: `nif-2.17` e `nif-2.18`, cada uma para `aarch64-apple-darwin`, `x86_64-apple-darwin`, `x86_64-linux-gnu`, `x86_64-linux-musl`, `aarch64-linux-gnu` e `aarch64-linux-musl`, entre outros (`gh release view v0.42.0 -R elixir-sqlite/exqlite`). O OTP 29 da máquina e o da imagem `1.20.4-erlang-29.1.2-alpine-3.24.2` reportam `nif_version` 2.18. Nenhum desses NIFs foi executado em Linux por mim com sucesso. (3) No nixpkgs, `beam.packages.erlang_29.elixir_1_20` existe e dá Elixir 1.20.4 com OTP 29.1.1; o atributo padrão `beamPackages.elixir` é o 1.18.5. Uma flake precisa fixar `beam.packages.erlang_29.elixir_1_20`, senão diverge da imagem de contêiner.

**D24. Extensões: o e01 entrega só os pontos de extensão (dono, 2026-10-14).**
- No e01: o behaviour `Enoch.Storage` e os metadados do schema legíveis por outros módulos.
- Registro e descoberta de extensões (configuração no `use Enoch.Repo` ou ambiente da aplicação) ficam para o e02, desenhados com os primeiros clientes: MySQL, Postgres, Absinthe e Ash.
- A suíte de contrato é um módulo reutilizável em `lib/` (por exemplo `use Enoch.Storage.ContractCase`), para que adaptadores externos a executem.
- Extensão interna é dependência opcional dentro do pacote `enoch`; externa é um pacote separado que implementa os mesmos behaviours. Os nomes de módulo não mudam entre as duas formas.

**D25. Termos Aplicação e Extensão (dono, 2026-10-14).** O dono confirmou os termos e os três tipos de extensão (storage, integração, domínio). Estão em `../../../../../CONTEXT.md`. A colisão de "aplicação" com "aplicação OTP" ficou resolvida no glossário: para o sentido do Erlang, diz-se "app OTP". O dono pode trocar o nome ("projeto", "app cliente") se preferir. O item 8 continua aberto para os demais termos.

**D26. Imutabilidade por atributo é opção do schema (dono, 2026-10-14).** Um atributo declarado com `immutable: true` não pode ser retraído nem alterado depois de afirmado. O transactor impõe a regra em todos os caminhos de escrita, inclusive um `transact` cru, e não apenas dentro de uma função de transação. Origem da necessidade: `canon/chat.md:373` e `:423`. Entra na s02, junto com o schema. Detalhes para a spec: o que vale na própria transação que afirma o valor, e a interação com a excisão (e02) e com a opção sem histórico (item 34).

**D27. Escrita em alto volume no e01: contrapressão, telemetria e medição (dono, 2026-10-14).**
- Fila limitada no transactor, com rejeição explícita quando enche. O BEAM não tem caixa de entrada limitada nativa, então a admissão é um mecanismo explícito: um contador em `:atomics` que o chamador incrementa antes de enviar a transação e que o transactor decrementa ao terminar; acima do limite, o chamador é rejeitado antes de a mensagem entrar na caixa de entrada. Filtrar dentro do transactor seria pior, porque a mensagem já teria ocupado a caixa. Não existe um `GenServer` com `max_queue`.
- Telemetria do tamanho da fila e das transações por segundo (D21).
- A documentação diz que uma transação com timeout pode ter sido aplicada, e que a defesa é a chave de idempotência com `unique: :identity` (D14).
- Uma medição de vazão do `Memory` e do SQLite na s04 ou s05, antes de qualquer otimização.
- Group commit, `transact_async` com várias transações em andamento e pipeline ficam para depois da medição, sem mudar a API. A opção sem histórico por atributo (`noHistory` no Datomic) conflita com o log imutável da D16 e precisa de decisão própria.
- Regra de vazamento do contador de admissão (vinda da revisão): quando o transactor cai, as mensagens que estavam na caixa de entrada morrem com ele e nunca são decrementadas, e o contador ficaria preso perto do limite. O `init` do transactor zera o contador, porque a caixa nova nasce vazia. Um chamador que morre entre incrementar e enviar também vazaria uma unidade; a spec deve escolher entre tratar esse caso e ler o tamanho da caixa de entrada do transactor (`Process.info(pid, :message_queue_len)`), que não tem vazamento mas é uma checagem aproximada. O teste de contrato "queda no meio da escrita" inclui a verificação de que o contador volta a zero.

**D28. A base `:history` entra no e01 (dono, 2026-10-14).** Revisa a D5, que a mandava para o e02. É a base sem o filtro de visibilidade: devolve afirmações e retrações, com `tx` e `added`, lidas do índice de histórico que a D16 já cria no e01 para o `as_of`. Entra na s03, junto com o `as_of`. Uma entidade ou um `pull` sobre uma base `:history` não faz sentido, porque há vários valores para o mesmo fato (`docs.datomic.com/reference/filters.html`: uma entidade é uma visão de um instante e não pode ser criada de uma base `history`); a spec define o comportamento. Os eventos de transação continuam no e02.

**D29. Evolução do schema entre deploys (dono, 2026-10-14).**
- Regras do instalador, na s02: atributo idêntico é no-op; atributo novo instala; alteração compatível aplica e é gravada como transação; alteração incompatível é erro explícito na subida, listando os conflitos. A lista exata do que é compatível ou incompatível sai na spec, tendo como referência a doc do Datomic (`docs.datomic.com/schema/schema-change.html`). Exemplos de incompatível: mudar o tipo, mudar a `scale` de um `:decimal` com dados, remover `immutable`, tornar único com duplicatas atuais.
- `deprecated: true`, na s02: o atributo continua legível e rejeita novas escritas, com aviso. Um atributo nunca é apagado (D16); a remoção de dados é a excisão (e02).
- Renomear, na s02: muda o nome do mesmo atributo. O log guarda o id do atributo (`canon/chat.md:71`), então o histórico segue intacto.
- Migração de dados versionada, na s05: um módulo que devolve dados de transação, aplicado uma vez, com o id da migração gravado como fato único; roda na subida, depois do schema e antes de aceitar escritas; se falhar, o sistema não sobe. O app de exemplo mostra uma evolução da versão 1 para a 2 (D17, critério 2).
- A tarefa de ensaio (mostrar o que a instalação faria contra o banco atual) e os geradores seguem o item 31.

**D30. Dados derivados no e01: leitura por regras e verificação (dono, 2026-10-14).**
- O e01 entrega a opção A: regras nomeadas e agregados (D9, D10). Entrega também a verificação de um atributo materializado contra uma regra: compara o valor gravado com o recálculo e aponta as divergências.
- A manutenção automática de atributo derivado declarado no schema (opção C) e os assinantes de eventos (opção D) ficam para o e02, desenhados com o ledger.
- Regra do projeto: um valor derivado nunca é fonte de verdade; precisa ser reconstruível a partir do log e verificável contra o recálculo.

**D31. Schema em dados, com a DSL de macros como açúcar (dono, 2026-10-14).**
- A forma canônica do schema é uma lista de definições de atributo, em dados. O instalador recebe essa lista (D29) e a compara com o que está gravado.
- A DSL de macros (`entity`/`attr`, `canon/chat.md:92-105`) gera exatamente esses dados e valida referências em tempo de compilação. O instalador valida de novo, porque os dados podem vir de qualquer lugar.
- Cada módulo, de aplicação ou de extensão, expõe uma lista de definições; o instalador junta as listas e detecta colisão de nomes de atributo entre módulos.
- Opções já decididas viram campos de dados: `scale` (D12), `immutable` (D26), `deprecated` (D29), `unique`, `index` e `cardinality`.
- Entra na s02. Se o custo apertar, a s02 entrega primeiro os dados e o instalador, e a DSL no fim da sprint.

**D32. API pública: núcleo funcional com nome de instância, macro como açúcar (dono, 2026-10-14).**
- O núcleo é uma API funcional que recebe o nome da instância: `Enoch.start_link(name: MyApp.Db, adapter: ..., schema: [...])` e `Enoch.transact(MyApp.Db, dados)`. A instância é criada em tempo de execução e identificada pelo nome.
- `use Enoch.Repo` é uma camada fina que gera funções delegando ao núcleo. Dois motivos para o núcleo funcional: um banco por tenant criado em tempo de execução (`canon/chat.md:235`) e um `:memory:` por teste (`canon/chat.md:208`) sem definir um módulo para cada banco. Segue o mesmo padrão da D31: dados no centro, macro por cima.
- A API pública do e01 expõe `transact`, `q`, `pull`, `db`, `as_of` e `history`. O `listen/1` do chat é de eventos e fica no e02 (D5). O instalador e as migrações rodam na subida.
- Cada instância sobe uma árvore de supervisão própria, com o processo dono das tabelas, o transactor e a admissão de transações (D18, D21, D27). O registro de extensões do e02 (D24) não pode ser impedido por esta API.
- Entra na s01, no esqueleto do `Enoch.Repo` (D22).

**D33. Cobertura dos recursos do Tickety no e01 (dono, 2026-10-14).** A referência é a contagem de usos em `_work/_Copland/Tickety/server/src` (item 36). O que entra:
- **s03, avaliador:** `get-else`, `missing?`, predicados de função `[(op ?x ...)]`, `or`, `or-join`, `not` e `not-join`. O `not` simples não tem uso no Tickety e entra por ser o mesmo mecanismo do `not-join` [INFERÊNCIA do agente].
- **s03, tempo:** o instante da transação (`:db/txInstant`) como atributo consultável da entidade de transação (D11) e o `as_of` por data, que resolve o instante para um `t` pelo `txInstant`.
- **s03, índices:** um invólucro público do `scan` do `Enoch.Storage` (D7) para acesso direto aos índices, equivalente ao `d/datoms`.
- **s02, escrita:** `:db/retractEntity` simples, que retrai todos os datoms atuais de uma entidade. A regra de `immutable` (D26) vale também aqui.
- **Ficam para o e02:** atributos componentes (`:db/isComponent`) com retração em cascata e `pull` dos componentes, e a navegação por entidade (`d/entity`), cujo uso `pull` e `q` cobrem.
- A contagem de ocorrências não prova que um recurso é essencial; o critério do corte é o que o avaliador e o contrato de storage já exigem ou o que é barato sobre o que já existe.

**D34. Sequência de subida do `Enoch.Repo` (dono, 2026-10-14).**
1. Abrir o storage e conferir a versão do layout; recusar um layout mais novo que o conhecido.
2. Conferir que o estado atual e o log concordam e reconstruir o atual se divergirem; no `Memory`, aplicar a recuperação do escritor (D21). Isso é feito pelo storage, antes de o transactor existir.
3. Iniciar o transactor com a admissão fechada a chamadores externos, aceitando só o caminho interno da subida (D27).
4. Registrar funções de transação e regras.
5. Instalar o schema (D29, D31).
6. Aplicar as migrações de dados pendentes, cada uma uma só vez (D29).
7. Abrir a admissão e emitir a telemetria da subida com a base.
- Uma falha em qualquer passo impede a subida, com erro explícito, e a admissão continua fechada.
- A verificação de um atributo materializado contra a sua regra (D30) não é um passo obrigatório: é a função `Enoch.verify_derived` e uma opção de subida, desligada por padrão.
- O Enoch não oferece um gancho de subida para a aplicação. O padrão (dados iniciais por upsert, reconciliador como processo supervisionado) fica documentado no app de exemplo.
- A versão do layout é gravada no storage; a forma exata (por exemplo `PRAGMA user_version` no SQLite) fica para a spec e não foi verificada.

**D35. Funções de transação e regras nomeadas: registro por lista de módulos (dono, 2026-10-14).**
- Cada módulo expõe uma lista de definições em dados. As funções de transação são pares `{nome, módulo}`, sendo o módulo o que implementa o behaviour de funções de transação (`canon/chat.md:343-354`, `:440`). As regras são definições com nome, argumentos e corpo.
- A instância recebe as listas de módulos nas opções, como o `schema:`: `Enoch.start_link(name: ..., schema: [...], functions: [MyApp.Fns, Ledger.Fns], rules: [Ledger.Rules])`. Uma transação chama `[:"ledger/post", dados]` e o transactor resolve o nome pelo registro do passo 4 da subida (D34). Uma consulta referencia as regras por nome; regras avulsas passadas na própria consulta continuam permitidas.
- O passo 4 recusa dois módulos que registrem o mesmo nome, com erro explícito, como o instalador faz com atributos (D31).
- Os nomes têm espaço de nomes, como os atributos (`ledger/post`, `ledger/balance`).
- Uma extensão de domínio é, portanto, uma lista de módulos de schema, uma de funções e uma de regras. A descoberta automática é o sistema de registro do e02 (D24).

**D36. Tipos de valor e comparação entre tipos (dono, 2026-10-14).** O dono confirmou a proposta com os ajustes da revisão.
- **Tipos do e01:** `:string`, `:long`, `:boolean`, `:ref`, `:keyword`, `:uuid`, `:instant` e `:decimal` (D12). Sem `:double`, `:bytes` nem `:uri`. O Tickety usa os oito (contagem em `_work/_Copland/Tickety/server/src/ticketeria/db/schema.clj`: `:ref` 50, `:string` 41, `:keyword` 24, `:uuid` 21, `:bigdec` 15, `:long` 14, `:instant` 14, `:boolean` 6).
- **Ordem dentro de cada tipo, definida pelo motor** (não pela afinidade da coluna do SQLite nem pela ordem de termos do Erlang): numérica para `:long`, `:decimal` e `:instant`; bytes de UTF-8 para `:string` e `:keyword`; `false` antes de `true` para `:boolean`; os 16 bytes, sem sinal, para `:uuid`; o id da entidade, como inteiro, para `:ref`.
- **`:instant`:** microssegundos desde a época, em inteiro, para a ordem ser igual no SQLite e no `Memory`. A unidade exata fica para a spec.
- **Cada atributo tem um único tipo.** Comparar dentro de um atributo nunca mistura tipos.
- **Literais de consulta** não têm tipo declarado; são interpretados pelo tipo do atributo a que a variável está ligada. `[(> ?preco 0)]` sobre um `:decimal` e `[(< ?t ~U[...])]` sobre um `:instant` são válidos.
- **Mistura numérica permitida, sempre exata, para ordem, igualdade e junção:** `:long` com `:decimal`, e `:decimal` com `:decimal` de escalas diferentes. O motor leva os dois lados à mesma escala antes de comparar, nunca compara o inteiro gravado de escalas diferentes. Assim `10 <= 10.00`, `10 >= 10.00` e `10 = 10.00` são todos verdadeiros, e uma junção entre uma variável `:long` e uma `:decimal` casa pelo valor exato. Um literal inteiro ou decimal vale como decimal exato; um literal com mais casas que a escala do atributo é permitido em comparação, porque não perde informação (a rejeição da D13 vale para escrita). Para o pushdown de `v` (D7), o literal vira um limite inteiro exato; numa igualdade ou junção, um valor que não é representável na escala do outro atributo (por exemplo `10,005` em escala 2) simplesmente não casa, sem erro.
- **Qualquer outra comparação de ordem entre tipos diferentes** (`<`, `>`, `<=`, `>=`) é erro explícito. **Igualdade e junção entre tipos não numéricos diferentes não casam** e não são erro: `"10"` não é igual a `10` (`canon/chat.md:70`). Este último detalhamento é do agente.
- Não há `:double`: um literal de ponto flutuante comparado com um `:decimal` é erro explícito.

**D37. `:decimal` na API é a struct `Decimal`, com `decimal ~> 3.2` (dono, 2026-10-14).**
- Fecha o item 39. O Enoch converte entre `Decimal` e o inteiro escalado (D12) nas fronteiras; a rejeição de excesso de casas (D13) e a ordem exata (D36) valem sobre o valor `Decimal`.
- Piso de versão por segurança: o `decimal` 2.4.1 tem dois avisos (`mix hex.audit`, 2026-10-14): EEF-CVE-2026-32686, expoente sem limite na entrada, corrigido na 3.0.0, e EEF-CVE-2026-97853, alocação sem limite em `Decimal.round/3`, corrigido na 3.1.2. A 3.2.0 (publicada em 2026-10-10, `elixir ~> 1.12`) compila e roda com Elixir 1.20.4 e OTP 29 e o `mix hex.audit` não acusou avisos. O Enoch exige `~> 3.2`.
- O expoente sem limite é relevante para o Enoch: valores `Decimal` vêm de entrada externa. A spec decide se o Enoch rejeita expoentes absurdos antes de converter, além da proteção da biblioteca. A escala por atributo e o limite de 64 bits (D12) já impõem um teto no que é gravado.

**D38. Stack e processo, em lote (dono, 2026-10-15).** O dono confirmou o lote do item 40 (a a h), com os ajustes abaixo.
- **Versões, sempre as mais recentes que funcionem:** `decimal` 3.2.0 (a mais recente; `mix hex.audit` sem avisos; Ecto 3.14.2, `ecto_sql` e `ecto_sqlite3` 0.25.0 pedem `decimal ~> 3.0`, e uma resolução real de `ecto` com `decimal ~> 3.2` e `exqlite` passou); Elixir 1.20.4 e OTP 29. No nixpkgs-unstable não existem `elixir_1_21` nem `erlang_30`; `beam.packages.erlang_29.elixir_1_20` dá Elixir 1.20.4 com OTP 29.1.1, enquanto a imagem `hexpm/elixir` tem OTP 29.1.2 (divergência de patch, aceita). A causa do `decimal` 2.4.1 na sondagem anterior não foi provada: nenhuma dependência da pilha exige `decimal`, então foi quase certamente o pin `~> 2.0` da própria sondagem [INFERÊNCIA].
- **Regra de entrada do `Decimal` (D37, vinda da revisão):** o Enoch nunca chama `Decimal.round/3` (a D13 proíbe arredondar). Na fronteira, antes de qualquer aritmética, confere o expoente e o número de dígitos do coeficiente contra a escala do atributo e o limite de 64 bits (D12) e rejeita com erro explícito, o que bloqueia valores como `1e999999999`.
- **Banco:** SQLite, via `exqlite` (D23).
- **Nix:** o flake serve para chamar, não só para entrar. Pedido do dono: usos práticos sem abrir o shell. Proposta de detalhe do agente, a ajustar na spec: `nix run .#test` roda a suíte, `nix run .#estado` roda `docs/_index/estado.sh`, `nix flake check` roda a suíte como verificação, e um pacote constrói a imagem do contêiner. O `devShell` continua existindo.
- **Contêiner mais leve:** base Alpine (`hexpm/elixir` `1.20.4-erlang-29.1.2-alpine-*`, cerca de 49 MB comprimidos, contra 80 a 103 MB das bases Debian e Ubuntu). Correção de 2026-10-15: a primeira versão desta linha dizia que o NIF pré-compilado para `aarch64-linux-musl` não existe. **Existe**: a release publica `nif-2.17` e `nif-2.18` para ele. O que se observou foi que, dentro do contêiner, o `exqlite` compilou da fonte depois de um `:enoent` ao baixar o NIF `2.17`; a causa desse `:enoent` não foi estabelecida (o contêiner não tem `curl`, tem `wget`; o OTP da imagem pede `2.18`). Duas tentativas de refazer o teste sem `build-base` falharam por timeout de rede do Hex dentro do contêiner, antes de chegar ao NIF. **Decisão:** o `Dockerfile` usa dois estágios, por prudência: compilar com `build-base` em `hexpm/elixir:1.20.4-erlang-29.1.2-alpine-*` e rodar o `mix release` numa imagem `alpine` enxuta só com as bibliotecas de execução (`libstdc++`, `ncurses-libs`, `openssl`). Se o NIF pré-compilado funcionar, o estágio de build deixa de precisar de `build-base`, e a spec simplifica.
- **Não verificado, e o app de exemplo da s05 precisa verificar:** o NIF pré-compilado em Alpine (`aarch64` e `x86_64`); o `mix release` rodando na imagem enxuta; e o modo WAL em **arquivo** sob musl (o teste anterior devolveu `memory` porque rodou em `:memory:`, que não suporta WAL). Só o `aarch64` musl chegou a abrir `:memory:` e uma tabela `STRICT` com coluna `ANY`. Uma imagem construída pelo flake, sem Docker, é a alternativa a avaliar na spec.
- **Tracker:** GitHub Issues, em `github.com/CaioFaSoares/EnochDB`. O registro de uso está em `docs/agents/README.md`. Fecha o item 10.
- **Lote a a h confirmado:** testes com ExUnit e `stream_data ~> 1.0` (só em teste); `telemetry ~> 1.0`; item 23 com uma transação de leitura por consulta, numa só conexão; item 31 com o app de exemplo da s05 como prova da experiência e sem geradores no e01; vocabulário do item 8, já escrito em `CONTEXT.md`.
- **Publicação:** o dono pediu publicar a documentação no remoto e criar uma primeira issue para popular a arquitetura de pastas na etapa `02_domain`, com um `CONTEXT.md` por pasta, sem gerar código. A arquitetura proposta está em `docs/arquitetura.md`.

## Em revisão

~~**D3. No e01 o único adaptador de storage é SQLite, com `:memory:` nos testes; o adaptador `Memory` (ETS) fica fora (dono, 2026-10-13).**~~
↳ [Superada — 2026-10-13 · D6 e D7]: o `Memory` entra no e01.

~~**D4. O Datalog do Enoch compila para SQL (dono, 2026-10-13).**~~
↳ [Superada — 2026-10-13 · D6]

## Descopado do e01

| Item | Destino | Motivo |
| --- | --- | --- |
| MySQL, Postgres | e02 | decisão do dono (D1) |
| Absinthe, Ash | e02 | decisão do dono (D1) |
| Litestream | e02 | decisão do dono (D1) |
| Corrente de hashes, excisão | e02 | decisão do dono (D1) |
| Regras recursivas | e02 | decisão do dono (D1 e D9) |
| Ledger e domínio financeiro | e03 | decisão do dono (D1) |
| ~~Histórico completo (`:history`)~~, eventos de transação | e02 (o `:history` foi para o e01 em D28) | decisão do dono (D5), alterada em D28 |
| Compilador de Datalog para SQL | descartado | decisão do dono (D6) |

## Abertas

Nada abaixo foi decidido. A recomendação do chat é hipótese.

1. ~~**Storage no e01.**~~ Fechada em D7.
2. ~~**Estratégia de consulta.**~~ Fechada em D6.
3. ~~**Fronteira `Enoch.Storage` no e01.**~~ Fechada em D7; o contrato temporal da varredura está no item 14.
4. ~~**Critério de aceite do e01.**~~ Fechada em D17.
5. ~~**Escopo da s01 dentro do e01.**~~ Fechada em D22.
6. ~~**Repositório e stack.**~~ Fechada em D23. Falta decidir como o ambiente de desenvolvimento é fixado (item 31).
7. ~~**Linguagem de schema.**~~ Fechada em D31.
8. ~~**Vocabulário.**~~ Fechada em D38: termos em `CONTEXT.md`. Termos novos entram quando surgirem.
9. ~~**Nome do pacote e dos módulos.**~~ Fechada em D23: `Enoch`.
10. ~~**Tracker.**~~ Fechada em D38: GitHub Issues.
11. ~~**Itens do framework sem casa.**~~ Fechada em D11.
12. ~~**Avaliador Datalog em memória no e01.**~~ Fechada em D6. Nota: a transação especulativa (aplicar sem gravar) não depende do avaliador; dá para fazê-la em SQL com `SAVEPOINT` e `ROLLBACK` no transactor.
13. ~~**Regras recursivas e agregados.**~~ Fechada em D9.
14. ~~**Base temporal da varredura.**~~ Fechada em D8.
15. ~~**Regras nomeadas não recursivas.**~~ Fechada em D10.
16. ~~**Codificação do `:decimal`.**~~ Fechada em D12.
17. ~~**Normalização do `:decimal`.**~~ Fechada em D13.
18. ~~**Onde a unicidade é garantida.**~~ Fechada em D14.
19. ~~**Consistência do banco como valor (`db` com `basis_t`) nos dois adaptadores.**~~ Fechada em D16.
21. ~~**Caminho rápido do presente.**~~ Fechada em D16: o presente é o índice atual.
20. ~~**Ordem dos valores.**~~ Fechada em D36.
22. ~~**Log completo versus intervalos de visibilidade.**~~ Fechada em D16.
23. ~~**Regra de consistência da escolha entre índice atual e histórico.**~~ Fechada em D38 para o SQLite: uma transação de leitura por consulta, numa só conexão, lendo o último `t` dentro dela e comparando com a base; se a base é menor, lê o histórico. No `Memory` vale o contador-base da D18.
24. ~~**Estrutura persistente do `Memory`.**~~ Fechada em D18: não há estrutura persistente; o `Memory` usa ETS.
25. ~~**Compartilhamento do `db` no `Memory` (BEAM).**~~ Fechada em D18. Contexto: no BEAM estruturas persistentes só compartilham memória dentro do heap de um processo, e o `persistent_term` dispara GC global a cada `put`. Por isso o `db` do `Memory` guarda referências a tabelas ETS e um `basis_t`, e não uma estrutura de dados.
26. **Salvaguardas do `Memory` contra consumir o servidor (D19 decidiu o limite de consulta; o resto é proposta do agente, a confirmar).**
    - **Eixos.** CPU: o scheduler do BEAM preempta por reduções, então uma consulta longa não trava o nó. Memória é o risco real. O ETS não conta para o `max_heap_size`.
    - **Cota de memória.** O transactor confere `:ets.info(tabela, :memory)` das duas tabelas antes de gravar. Acima de `max_memory`, rejeita a transação com erro explícito, como o estouro de 64 bits do `:decimal` (D12). Leituras continuam funcionando. A obrigatoriedade do `max_memory` está fechada em D20.
    - **Sobrevivência das tabelas.** As tabelas ETS pertencem a um processo separado do transactor, com `heir`, para não morrerem junto com ele.
    - **Recuperação do escritor.** A escrita de uma transação no ETS não é atômica: são várias linhas e vários índices. Uma queda no meio da transação `t+1` deixa linhas órfãs com `tx = t+1` e o contador em `2t+1`. Regra corrigida em 2026-10-13, vinda da revisão: a recuperação **nunca volta o contador**. Voltar de `2t+1` para `2t` reabriria o ABA: um leitor que leu `2t`, varreu a tabela atual durante a escrita que caiu e releu `2t` aceitaria uma leitura rasgada. Ao reiniciar, antes de aceitar escrita: (1) manter o contador em `2t+1`, de modo que os leitores vão ao histórico, onde as órfãs `tx = t+1` ficam invisíveis para `b <= t`; (2) apagar do histórico as linhas com `tx = t+1`; (3) reconstruir a tabela atual a partir do histórico até `t`; (4) publicar `2(t+1)`. O `t+1` vira uma transação vazia (queimada) e a próxima transação real é `t+2`. Isso torna obrigatória a alternativa de nunca reutilizar um `t`. Custo: O(histórico) no reinício e uma lacuna em `t`, aceitáveis porque o `Memory` é volátil.
    - **Teste de contrato obrigatório:** "queda no meio da escrita", com um leitor em curso durante a recuperação, nos dois adaptadores quando aplicável.
    - **Limite do que o BEAM protege.** A garantia contra a VM inteira ser morta pelo sistema operacional é o limite de memória do contêiner ou do sistema, que fica fora do Enoch.
    - **Volatilidade.** O `Memory` perde tudo ao reiniciar o nó, então não serve de evidência de auditoria. A auditoria vive no log do SQLite (D16).
    - **Prova de conceito na spec:** varredura de `ordered_set` com inserção concorrente, seqlock sob escrita contínua, recuperação após queda no meio da escrita e comportamento ao atingir `max_memory`.
27. **Funções de transação dentro do transactor.** No desenho do chat, o transactor roda as funções de transação (`canon/chat.md:124`). Um laço infinito numa função (`cas`, `post`) prenderia todas as escritas, e o `max_heap_size` da consulta (D19) não cobre isso. Questão: as funções rodam num processo com tempo e heap limitados, cuja morte aborta só aquela transação? Recomendação do agente: sim, com o transactor intacto.
    Confirmado em D21.
28. **Desenho do sistema de salvaguardas do `Memory`.** O dono quer um sistema, não só um limite (D20). Proposta do agente, a confirmar. Componentes:
    - **Limite duro:** `max_memory` na escrita, com erro explícito (item 26). Com `:infinity`, o Enoch registra um aviso na subida dizendo que só o sistema operacional protege a máquina.
    - **Limite brando:** um percentual de `max_memory` (valor a decidir) que emite um evento de alerta antes de a escrita ser rejeitada, para quem opera agir a tempo.
    - **Limites de consulta:** `max_heap_size` e tempo limite por consulta, com a consulta morta e o erro explícito (D19).
    - **Limites de função de transação:** item 27.
    - **Supervisão:** processo dono das tabelas separado do transactor, com `heir`, sob a árvore `:rest_for_one` do chat (`canon/chat.md:252-263`).
    - **Recuperação do escritor:** regra do item 26, mais o teste de contrato "queda no meio da escrita".
    - **Observabilidade:** eventos de telemetria para memória usada, consultas mortas por limite, transações rejeitadas por cota e linhas lidas por varredura (a mesma métrica do critério 3 da D17).
    Questão: o dono confirma esses componentes, ou quer tirar ou acrescentar algum? O limite brando entra no e01?
    Confirmado em D21.
29. ~~**API pública e árvore de supervisão (`Enoch.Repo`).**~~ Fechada em D32.
30. ~~**Sistema de extensões.**~~ Fechada em D24. Os nomes dos tipos de extensão e da aplicação estão no item 32.
31. ~~**Experiência de desenvolvimento: novo projeto, schema e contêineres.**~~ Fechada em D38: o app de exemplo da s05 prova a experiência; contêiner Alpine em dois estágios; flake com comandos de uso; sem geradores no e01.
32. ~~**Nomes: aplicação, extensão e biblioteca de domínio.**~~ Fechada em D25.
33. **O que o e01 precisa expor para uma extensão de domínio existir depois.** A extensão de domínio (por exemplo o ledger, no e03) compõe o núcleo por: (a) schema em vários módulos instalados juntos, de forma aditiva; (b) funções de transação registradas por nome; (c) regras nomeadas importáveis; (d) convenção ou verificação de colisão de nomes de atributo entre extensões. Isso toca o item 7 (linguagem de schema). A imutabilidade por atributo, que também estava aqui, foi fechada em D26.
    Atualização de 2026-10-14 (D31): os pontos (a), schema em vários módulos instalados juntos, e (d), colisão de nomes de atributo, ficam resolvidos pela forma em dados. Continuam abertos (b), funções de transação registradas por nome, e (c), regras nomeadas importáveis.
    Fechada em D35.
34. **Escrita em alto volume.** O dono perguntou como lidar com isso como o Datomic. O que a documentação do Datomic diz: o transactor processa as transações em série (`transactions/transaction-processing.html`); cada escrita é fortemente serializável, com um CAS no storage (`transactions/acid.html`); sob carga o Datomic usa lotes, estruturas transitórias e persistentes para que a média de escritas por transação seja uma ou menos (`transactions/acid.html`); o transactor aplica contrapressão quando o índice em memória passa de `memory-index-max` e desacelera radicalmente (`operation/capacity.html`); para importações recomenda `transact-async` com várias transações em andamento e agrupar datoms em transações quando o agrupamento não tem significado semântico (`operation/capacity.html`); recomenda enfileirar tudo o que não precisa de resposta síncrona e limitar a taxa (`operation/capacity.html`, "Queue Transactions"); manda guardar registros e não logs operacionais de alto volume, e declarar `noHistory` nos atributos cujo passado não importa (`operation/capacity.html`, "Store What You Need"); e recomenda um transactor por banco para bancos grandes ou críticos (`operation/capacity.html`, "Multiple Databases"). Não encontrei na documentação um número de transações por segundo. O Datomic não escala escrita horizontalmente: ele a administra. Pontos do chat: o group commit acumula chamadas por alguns milissegundos e grava numa transação SQLite só (`canon/chat.md:149`); com timeout o chamador não sabe se a transação foi aplicada (o chat usa `GenServer.call` com 15 s, `canon/chat.md:132`; o Datomic descreve a mesma incerteza em `transactions/transaction-processing.html`). Opções para o Enoch, com recomendação do agente: (1) no e01, fila limitada no transactor com rejeição explícita ao encher, telemetria de tamanho da fila e de transações por segundo (D21), documentação de que uma transação com timeout pode ter sido aplicada, e uma medição de vazão do `Memory` e do SQLite na s04 ou s05 antes de qualquer otimização; (2) no e02 ou quando a medição pedir: group commit, `transact_async` com várias transações em andamento e a opção sem histórico por atributo, que conflita com o log imutável da D16 e com a hash chain, e por isso precisa de decisão própria; (3) fora do Enoch: escrita horizontal e logs operacionais. Vários repos independentes por aplicação, cada um com seu transactor, é o análogo do transactor por banco e depende do item 29. O dono não confirmou nada disto.
    Fechada em D27 quanto ao e01. O resto permanece como proposta para o e02.
35. **Sequência de subida do `Enoch.Repo`: validar, recuperar e construir sobre o que já existe.** O dono quer que, ao rodar, o sistema de dados seja validado e recuperado, ou construído sobre o que já foi feito. Referência: o `-main` do Tickety (`_work/_Copland/Tickety/server/src/ticketeria/core.clj`) conecta (criando o banco se faltar e repetindo até o transactor subir, `db/connection.clj`), instala o schema de forma idempotente (`db/schema.clj`), instala as funções de transação, garante o administrador de bootstrap e o seed por ids fixos, e inicia um reconciliador em segundo plano (`jobs/reconciler.clj`). Proposta do agente para o Enoch, a confirmar: (1) abrir o storage e conferir a versão do layout; (2) conferir que o estado atual e o log concordam, e reconstruir o estado atual se não concordarem (D16, D17); (3) instalar o schema de forma aditiva e idempotente, recusando com erro explícito, na subida, uma alteração incompatível com o que já está gravado (por exemplo mudar a `scale` de um `:decimal` com dados, que reinterpretaria os inteiros gravados); (4) registrar funções de transação e regras; (5) zerar o contador de admissão e iniciar o transactor (D27); (6) emitir um evento de telemetria da subida com a base. Bootstrap de dados e jobs de reconciliação são da aplicação, não do núcleo: o núcleo oferece upsert idempotente (D14), metadados de transação (D11) e consultas. Questões: a política de alteração de schema (só aditiva, com recusa das incompatíveis) e a lista do que conta como incompatível; se o núcleo oferece um gancho de subida para a aplicação ou só documenta o padrão no app de exemplo (recomendação do agente: só documentar).
    Fechada em D34. A sequência corrigida (D34) substituiu a proposta original deste item, que se contradizia: o schema e as migrações gravam transações, mas o transactor só subia no passo 6, e as funções e regras eram registradas depois das migrações.
36. **Cobertura dos recursos do Datomic que o Tickety usa.** Contagem de usos em `_work/_Copland/Tickety/server/src` em 2026-10-14: `d/q` 118, `d/pull` 75, forma `:find ?x .` (escalar) 63, `:db/txInstant` 32, tempids 15, `d/history` 9, `:db/retract` 9, `d/datoms` 8, `d/basis-t` 7, lookup refs 6, `d/entity` 5, `d/as-of` 2, `:db/isComponent` 2, `:db/retractEntity` 2, `datomic.tx` 2, `d/sync` 1. Sem uso: `:db/cas`, `d/with`, `d/since`, `d/log`, fila de relatórios de transação, texto completo, `noHistory`, `index-range`. Itens que o sistema real usa e que nenhuma decisão do grilling cobre: (a) atributos componentes (`:db/isComponent`) e `:db/retractEntity` com cascata; (b) o instante da transação como atributo consultável (`:db/txInstant`) em consultas e `pull`; (c) acesso direto a índices (`datoms`); (d) navegação por entidade (`d/entity`); (e) as formas de `:find` escalar e de coleção e `:in` com parâmetros, nas consultas e dentro das funções de transação, que recebem o `db` do início da transação. Os itens (e) e o `pull` aninhado entram naturalmente no avaliador (s03). Questão: quais de (a) a (d) entram no e01, quais ficam para o e02 e quais são descartados? Esta lista é contagem de ocorrências, não prova de que o recurso é essencial.
    Fechada em D33. Complemento de 2026-10-14, corrigido após revisão. Contagem de cláusulas Datalog: `get-else` 8, predicados de função `[(op ?x ...)]` 16, `or-join` 1, `not-join` 1, `or` com `and` 1 (`db/stock.clj:47`), `missing?` 1; `not` ou `or` simples com cláusulas: 0; regras passadas como entrada (`:in $ %`): 0. As contagens de `(not `, `(or ` e ` %` (164, 213 e 42) eram código Clojure e foram descartadas. `d/basis-t` (7) mapeia para o `basis_t` do `db` (D18); `d/sync` (1) só importa com vários nós (e02); o `:history` foi tratado em D28.
37. **Evolução do schema entre deploys: regras do instalador, renomear, deprecar e migrar dados.** O dono considera isso muito importante e quer uma forma de migrar ou deprecar atributos antigos. Referência do Datomic (`docs.datomic.com/schema/schema-change.html`): mudar um atributo é transacionar fatos novos sobre ele; uma mudança que viola uma invariante aborta a transação, e para habilitá-la é preciso antes mudar os dados (por exemplo, retrair valores duplicados antes de tornar o atributo único); renomear o `:db/ident` é permitido, e o nome antigo e o novo apontam para a mesma entidade; mudar a cardinalidade de muitos para um exige no máximo um valor por entidade; `:db/unique` exige cardinalidade um, valores únicos entre as afirmações atuais e, no Datomic Pro, o índice AVET já mantido; adicionar unicidade não altera o histórico, que pode ter valores repetidos; `:db/valueType` nunca pode ser alterado; o schema vale o da base corrente, e viajar no tempo não volta o schema. O Tickety instala o schema em duas passadas por causa do índice antes do `unique` (comentário em `install!`, `db/schema.clj`). Proposta do agente para o Enoch, a confirmar. Regras do instalador: atributo idêntico é no-op; atributo novo instala; alteração compatível (índice, documentação, `unique` sem duplicatas atuais, cardinalidade de muitos para um sem conflitos) aplica e é gravada como transação; alteração incompatível (tipo, escala de um `:decimal` com dados, remover `immutable`, `unique` com duplicatas) é erro explícito na subida. Ciclo de vida: `deprecated: true` mantém o atributo legível e rejeita novas escritas, com aviso; um atributo nunca é apagado (D16), e a remoção de dados é a excisão (e02). Renomear é mudar o nome do mesmo atributo: o log guarda o id do atributo (`canon/chat.md:71`), então o histórico segue intacto. Migração de dados: um módulo versionado que devolve dados de transação, aplicado uma vez, com o id da migração gravado como fato único, executado na subida depois do schema e antes de aceitar escritas, e uma falha impede a subida. O chat diz que não há migrations de tabela (`canon/chat.md:105`), mas não trata de migrar dados. Questões: (a) o que entra no e01; recomendação do agente: regras do instalador, `deprecated` e renomear na s02, e migração de dados versionada na s05, com o app de exemplo mostrando uma evolução da versão 1 para a 2; (b) a tarefa de ensaio (mostrar o que a instalação faria contra o banco atual) e os geradores seguem o item 31.
38. **Dados derivados mais perto do núcleo.** O dono quer entender como levar saldos e outros valores derivados para perto do núcleo. No Tickety nada é materializado: o saldo é sempre derivado por consulta (ADR-0003, citado em `db/payments.clj` e `db/history.clj`). No chat, o saldo é somado a cada consulta e, quando ficar lento, vira uma projeção mantida pelo transactor na mesma transação ou por um assinante de eventos, sempre reconstruível a partir do log (`canon/chat.md:404-406`). Opções. A (leitura): regras nomeadas e agregados (D9, D10); sem armazenamento extra e correto em qualquer `as_of`, com custo proporcional aos fatos envolvidos. B (na transação): uma função de transação que também grava o valor derivado como datoms; consistente com o `as_of` e com leitura O(1), com risco de divergência se a função tiver um erro. C (declarado no schema): atributo derivado associado a uma regra, escrito só pelo motor, mantido na mesma transação, com verificação e reconstrução oferecidas pelo núcleo; o difícil é a manutenção incremental, porque recalcular as entidades afetadas custa o tamanho dos fatos delas, e só agregados simples admitem atualização por delta. D (assinante de eventos): eventualmente consistente, fica no e02. Regra do projeto: um valor derivado nunca é fonte de verdade; precisa ser reconstruível a partir do log e verificável contra o recálculo. Recomendação do agente: o e01 entrega A e a verificação de um atributo materializado contra uma regra (a primitiva de que o C precisa); a manutenção automática do C entra no e02, desenhada com o ledger. Questão: o dono quer o C já no e01?
    Itens 37 e 38 fechados em D29 e D30.
39. ~~**Representação do `:decimal` na API.**~~ Fechada em D37.
40. ~~**Pequenas decisões de stack, em lote.**~~ Confirmada em D38.
