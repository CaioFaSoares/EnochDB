# Spec — e01 `nucleo-enoch` (sprint s01-nucleo-enoch, etapa 03_spec)

> **Missão:** converter as decisões D1 a D42 em requisitos com aceite observável, sem reabrir o grilling e sem acrescentar escopo. Toda decisão fechada aparece como requisito (R#) ou como fora de escopo (F#). O que a spec não pode decidir está em "Pendências do dono".

## Origem

- Decisões: [`../../01_grilling/handovers/decisoes.md`](../../01_grilling/handovers/decisoes.md). As decisões são citadas por número; o texto delas não é copiado aqui.
- ADRs e handover da `02_domain`: [`../../../../adr/`](../../../../adr/), [`../../02_domain/handovers/adrs.md`](../../02_domain/handovers/adrs.md).
- Glossário: [`../../../../../CONTEXT.md`](../../../../../CONTEXT.md). Canon: [`../../../../canon.md`](../../../../canon.md). Árvore de pastas: [`../../../../arquitetura.md`](../../../../arquitetura.md).
- Não há código no repositório; não existe `spec-tecnica.md`. A D3 e a D4 estão riscadas em `decisoes.md` (superadas por D7 e D6) e não geram requisito.

## Como ler

Cada requisito traz as decisões que o justificam, o aceite observável e a sprint do e01 que o entrega (D22). Os testes citados são testes de contrato ou de propriedade (`stream_data`, D38) executados com `mix test`. "Dois adaptadores" é o `Enoch.Adapters.Memory` e o `Enoch.Adapters.SQLite`.

## Escopo por sprint (D22)

| Sprint | Entrega |
| --- | --- |
| s01 | contrato `Enoch.Storage`; adaptador `Memory`; transactor com `add` e `retract` crus; árvore de supervisão e esqueleto do `Enoch.Repo`; suíte de contrato inicial; contador de linhas lidas; esqueleto da subida (passos 1, 2, 3 e 7), versão do layout como método do contrato, admissão fechada e aberta, mecanismo de registro de funções e regras sem conteúdo (D34, D35, atribuição do agente aceita junto com o conjunto) |
| s02 | schema (dados, DSL, bootstrap, registro, instalador); tipos, cardinalidade, `:decimal`; unicidade e upsert; tempids, lookup refs, `cas`, metadados de transação, `:db/retractEntity`; `immutable`, `deprecated`, renomear; registro das funções de transação e o passo do schema |
| s03 | avaliador Datalog; `pull`; `as_of` por `t` e por data; base `:history`; `txInstant`; invólucro do `scan`; limites de consulta; registro das regras nomeadas; `Enoch.verify_derived` |
| s04 | adaptador SQLite; versão do layout gravada e conferida; a suíte de contrato passa nos dois adaptadores |
| s05 | `max_memory`, limite brando, funções de transação limitadas, telemetria; migração de dados versionada; app de exemplo e fechamento da D17 (critério 2) |
| proposta (P1) | manutenção automática de atributo derivado (D39) na s05: depende do schema da s02 e das regras da s03; a D22 não a atribui e o dono confirma no gate |

## Requisitos

### Storage e adaptadores

**R1. Contrato de varredura, sem compilador de consulta** (D6, D7, D15 superada). O `Enoch.Storage` expõe varreduras dos índices e pushdown mínimo (filtros por `a`, `v` e `t`). Joins, regras e semântica ficam no avaliador. O contrato não tem `compile/2`. *Aceite:* nenhum callback do `Enoch.Storage` recebe uma consulta Datalog; a suíte de contrato roda os mesmos casos de varredura e de pushdown nos dois adaptadores. *Sprint:* s01 (contrato), s04 (segundo adaptador).

**R2. Modelo acumulativo** (D16, D15 superada, D8 restabelecida). Nenhuma linha de dados é alterada no lugar; retrair grava um datom com `added = false`. No SQLite, `datoms_log` é só `INSERT`, protegido por gatilhos, com índices covering EAVT, AEVT, AVET (atributos indexados) e VAET (refs), todos com `v` e `tx`; `datoms` é o estado atual, só com datoms vivos, gravado na mesma transação SQL e sem colunas `added_tx` e `retracted_tx`. *Aceite:* `UPDATE` e `DELETE` no log são rejeitados; afirmar, retrair e reafirmar o mesmo `(e, a, v)` deixa três linhas no log e um datom no estado atual; o estado atual reconstruído do log é idêntico ao gravado. *Sprint:* s01 (`Memory`), s04 (SQLite).

**R3. Escolha do índice pela base** (D16, D8, D28). `:current`, ou `basis_t` igual ao último `t`, lê o estado atual. `{:as_of, t}`, banco como valor antigo e `:history` leem o histórico, onde o avaliador resolve a visibilidade: vale o último operador por `(e, a, v)` com `tx <= b`, e as linhas do mesmo `(e, a, v)` chegam adjacentes e ordenadas por `tx`. *Aceite:* para o mesmo `db`, `q` devolve o mesmo resultado antes e depois de transações posteriores; uma retração posterior não altera `as_of` anterior; um teste de propriedade (`stream_data`) gera históricos aleatórios de afirmações e retrações e confere que `as_of` coincide com um modelo de referência que aplica "o último operador por `(e, a, v)` com `tx <= b`", nos dois adaptadores. *Sprint:* s03.

**R4. `Memory` em ETS com contador como base** (D18, D16 ressalvada). Duas tabelas ETS (histórico `ordered_set` só com inserção e estado atual); o banco como valor é `{referências, basis_t}` e custa O(1). Um contador em `:atomics` é a base: `2t` com a base estável em `t`, `2t+1` enquanto a transação `t+1` escreve; `basis_t = div(contador, 2)`. Um leitor com base `b` só usa o estado atual se o contador valer `2b` antes e depois da varredura; senão refaz aquela varredura pelo histórico na mesma base, sem repetir em laço. O contador nunca diminui. *Aceite:* teste de leitura concorrente com escrita contínua termina e é consistente com a base; teste obrigatório (D18): banco de base `L` com a transação completa `L+1` aplicada antes da varredura lê consistente com `L`. *Sprint:* s01.

**R5. Recuperação do transactor e supervisão** (D21, D18). Após a queda no meio de uma transação, o contador fica em `2t+1`; as linhas órfãs `tx = t+1` são apagadas do histórico; o estado atual é reconstruído a partir do histórico até `t`; o contador é publicado em `2(t+1)`; a transação `t+1` fica vazia e a próxima real é `t+2`. As tabelas pertencem a um processo separado do transactor, com `heir`. *Aceite:* teste de contrato "queda no meio da escrita", com leitor em curso durante a recuperação, nos dois adaptadores quando aplicável; confere também que o contador de admissão volta a zero. *Sprint:* s01.

**R6. Contador de linhas lidas** (D17 critério 3, D18). O adaptador expõe o número de linhas lidas por varredura. *Aceite:* uma consulta ao presente lê o mesmo número de linhas antes e depois de N retrações do atributo, nos dois adaptadores; o benchmark de tempo é complemento, não gate. *Sprint:* s01 (contador), verificado de novo na s04.

**R7. Persistência do SQLite** (D17 critério 4, D16). *Aceite:* um banco SQLite em arquivo sobrevive a reinício e o estado atual reconstruído a partir do log é idêntico ao gravado. *Sprint:* s04.

**R8. Consultas e índices do SQLite no papel** (D22, mitigação aceita). Esta spec escreve, sem implementar, as consultas e os índices do SQLite para o contrato de varredura (item 23). Está no Anexo A. *Aceite:* o Anexo A existe e cobre as quatro varreduras e a leitura do último `t`. *Sprint:* s01 (documento).

### Transactor e escrita

**R9. Unicidade e upsert no transactor** (D14). A semântica de `unique` e do upsert por `unique: :identity` é garantida pelo transactor para qualquer adaptador. O contrato do adaptador não tem mecanismo de unicidade; o índice único parcial do SQLite é só rede de segurança. *Aceite:* os mesmos casos de unicidade e upsert passam nos dois adaptadores; duas escritas do mesmo valor único: a segunda falha, ou faz upsert se o atributo é `:identity`. *Sprint:* s02.

**R10. `immutable` por atributo** (D26, D33). Um atributo com `immutable: true` não pode ser retraído nem alterado depois de afirmado, em todos os caminhos de escrita, inclusive um `transact` cru e `:db/retractEntity`. *Aceite:* retrair ou alterar um atributo imutável é erro explícito por qualquer caminho. *Sprint:* s02. O que vale na própria transação que afirma o valor e a interação com a excisão e com a opção sem histórico estão na proposta P3.

**R11. Forma das transações** (D5, D11, D33). A transação aceita mapas e operações de afirmar e retrair, tempids, lookup refs, a função `cas` e metadados de transação (`tx/user`, `tx/reason`, `tx/source`) como atributos da entidade de transação; `:db/retractEntity` retrai todos os datoms atuais de uma entidade. A retração implícita de cardinalidade um depende do schema e fica na s02. *Aceite:* a suíte de contrato cobre tempids, lookup refs e `cas`; um `cas` com valor esperado diferente falha sem gravar; metadados de transação são consultáveis. *Sprint:* s01 (`add` e `retract` crus), s02 (o restante).

**R12. Funções de transação limitadas** (D21, D27, D35). Funções de transação são pares `{nome, módulo}` e rodam num processo próprio com tempo e heap limitados; a morte do processo aborta só aquela transação e o transactor segue. *Aceite:* uma função em laço infinito é morta pelo limite, devolve erro explícito e a transação seguinte é aceita. *Sprint:* s02 (registro e chamada), s05 (limites).

**R13. Admissão limitada** (D27, D34). Um contador de admissão em `:atomics` é incrementado pelo chamador antes de enviar a transação e decrementado pelo transactor ao terminar; acima do limite o chamador é rejeitado antes de a mensagem entrar na caixa de entrada. O `init` do transactor zera o contador. A admissão tem estado fechado (só o caminho interno da subida) e aberto. A documentação diz que uma transação com timeout pode ter sido aplicada e que a defesa é uma chave de idempotência com `unique: :identity`. *Aceite:* acima do limite o chamador recebe rejeição explícita; após a queda do transactor o contador de admissão volta a zero; com a admissão fechada, uma escrita externa é rejeitada. *Sprint:* s01 (mecanismo e estados), s05 (telemetria). [PROPOSTA] Para o chamador que morre entre incrementar e enviar (D27 manda a spec escolher): manter o contador e reconciliá-lo com `Process.info(pid, :message_queue_len)` sempre que o transactor está sem transação em andamento, corrigindo o contador para o tamanho real da caixa; um chamador rejeitado desfaz o próprio incremento. Como a admissão nasce fechada (D34, passo 3), nenhum incremento antecede o `init`. *Aceite da proposta:* matar um chamador entre incrementar e enviar deixa o contador igual ao tamanho da caixa depois da reconciliação.

**R14. Medição de vazão antes de otimizar** (D27). Uma medição de vazão do `Memory` e do SQLite acontece na s04 ou s05, antes de qualquer otimização. *Aceite:* existe um relatório de vazão dos dois adaptadores. *Sprint:* s04 ou s05.

### Salvaguardas

**R15. Limites de consulta** (D19, D21). Cada consulta roda num processo próprio com `max_heap_size` e tempo limite; ao estourar, morre só esse processo e o chamador recebe um erro que nomeia o limite; a consulta não deixa estado. *Aceite:* uma consulta que estoura o heap e outra que estoura o tempo devolvem erros distintos; a chamada seguinte, com `db()` novo, funciona. *Sprint:* s03.

**R16. `max_memory` e limite brando** (D20, D21). `max_memory` é obrigatório no `Memory`; sem ele o adaptador não sobe, com erro claro; `:infinity` é permitido e a subida registra um aviso. O transactor confere `:ets.info(tabela, :memory)` antes de gravar e rejeita a transação acima do limite, com erro explícito; as leituras seguem funcionando. O limite brando, um percentual de `max_memory`, emite um alerta antes da rejeição. [PROPOSTA] O percentual do limite brando é 80% de `max_memory` (D21 manda a spec fixá-lo), configurável. *Aceite:* sem `max_memory` o `Memory` não sobe; acima do limite a escrita é rejeitada e a leitura funciona; o alerta sai ao cruzar o limite brando e antes da rejeição. *Sprint:* s05 para a cota e o alerta. Na s01 o `Memory` já exige a opção `max_memory` (aceita `:infinity` e ignora o valor até a s05), para a D20 valer desde o início sem implementar a cota (confirmado pelo dono em 2026-10-15).

**R17. Telemetria** (D21, D27, D34). Eventos para memória usada, consultas mortas por limite, transações rejeitadas por cota, linhas lidas por varredura, tamanho da fila, transações por segundo e a subida com a base. *Aceite:* um teste captura cada evento com `:telemetry`. *Sprint:* a telemetria da subida (passo 7) na s01 (D34); os demais eventos na s05; o contador de linhas lidas vem da s01.

### Tipos e valores

**R18. `:decimal`** (D12, D13, D37, D38). Inteiro escalado, com a escala fixa por atributo e declarada no schema; 64 bits, estouro é erro explícito; mais casas que a escala é rejeitado, menos casas é aceito e normalizado; o tipo não conhece moeda. Na API é a struct `Decimal` (`decimal ~> 3.2`); o Enoch nunca chama `Decimal.round/3` e, antes de qualquer aritmética, confere o expoente e o número de dígitos contra a escala e o limite de 64 bits. *Aceite:* `1,5` em escala 2 grava `150`; `1,505` em escala 2 é rejeitado; `1e999999999` é rejeitado antes de qualquer conta; um valor que excede 64 bits é erro; a soma de agregados é exata. *Sprint:* s02.

**R19. Tipos do e01 e ordem** (D36). Os tipos são `:string`, `:long`, `:boolean`, `:ref`, `:keyword`, `:uuid`, `:instant` e `:decimal`; sem `:double`, `:bytes` nem `:uri`. A ordem em cada tipo é definida pelo motor: numérica para `:long`, `:decimal` e `:instant`; bytes de UTF-8 para `:string` e `:keyword`; `false` antes de `true`; os 16 bytes sem sinal para `:uuid`; o id inteiro para `:ref`. `:instant` são microssegundos desde a época. [PROPOSTA] A época é a Unix (1970-01-01T00:00:00Z), em inteiro de 64 bits (D36 deixa a unidade exata para a spec). *Aceite:* a mesma sequência de valores ordena igual nos dois adaptadores; a suíte de contrato cobre cada tipo. *Sprint:* s02.

**R20. Comparação entre tipos** (D36). Cada atributo tem um único tipo; literais de consulta são interpretados pelo tipo do atributo a que a variável está ligada. A mistura numérica (`:long` com `:decimal`, e `:decimal` de escalas diferentes) é exata em ordem, igualdade e junção; um literal com mais casas que a escala do atributo é permitido numa comparação, porque não perde informação, e a rejeição da D13 vale só para a escrita. Qualquer outra comparação de ordem entre tipos diferentes é erro; igualdade e junção entre tipos não numéricos diferentes não casam, sem erro; um literal de ponto flutuante contra um `:decimal` é erro. *Aceite:* `10 = 10.00`, `10 <= 10.00` e `10 >= 10.00` são verdadeiros; `"10"` não é igual a `10`; `(< ?x "a")` sobre um `:long` é erro; `10,005` em escala 2 numa junção não casa e não é erro; `[(> ?preco 10.005)]` sobre um `:decimal` de escala 2 é válido. *Sprint:* s03.

### Schema

**R21. Schema em dados** (D31). A forma canônica é uma lista de definições de atributo, em dados; a DSL `entity`/`attr` gera esses dados e valida referências em compilação; o instalador valida de novo, junta as listas de vários módulos e detecta colisão de nomes de atributo. As opções viram campos: `scale`, `immutable`, `deprecated`, `unique`, `index`, `cardinality`. *Aceite:* um schema escrito em dados e o mesmo escrito pela DSL instalam o mesmo conjunto de atributos; dois módulos com o mesmo nome de atributo falham com erro explícito. *Sprint:* s02; se o custo apertar, a s02 entrega primeiro os dados e o instalador, e a DSL no fim.

**R22. Instalador e evolução do schema** (D29). Atributo idêntico é no-op; atributo novo instala; alteração compatível aplica e é gravada como transação; alteração incompatível é erro explícito na subida, listando os conflitos. `deprecated: true` mantém o atributo legível e rejeita novas escritas, com aviso. Renomear muda o nome do mesmo atributo e o histórico segue intacto. [PROPOSTA] Lista exata (D29 manda a spec fixá-la, com referência a `docs.datomic.com/schema/schema-change.html`): compatível é adicionar índice, mudar a documentação, tornar `unique` sem duplicatas atuais, mudar a cardinalidade de muitos para um sem conflitos, marcar `deprecated` e renomear; incompatível é mudar o tipo, mudar a `scale` de um `:decimal` com dados, remover `immutable` e tornar `unique` com duplicatas atuais. *Aceite:* cada caso da lista tem um teste; renomear não perde histórico; escrever num atributo `deprecated` falha e a leitura funciona. *Sprint:* s02.

**R23. Migração de dados versionada** (D29). Um módulo devolve dados de transação, é aplicado uma vez, com o id da migração gravado como fato único; roda na subida, depois do schema e antes de aceitar escritas; se falhar, o sistema não sobe. *Aceite:* uma migração roda uma só vez em duas subidas; uma migração que falha impede a subida. *Sprint:* s05. A tarefa de ensaio e os geradores seguem o item 31 (D38): sem geradores no e01.

**R24. Registro de funções e regras por módulos** (D35, D24). A instância recebe as listas de módulos nas opções (`schema:`, `functions:`, `rules:`); os nomes têm espaço de nomes; o passo 4 da subida recusa, com erro explícito, dois módulos que registrem o mesmo nome. Uma consulta referencia regras por nome e regras avulsas continuam permitidas. *Aceite:* dois módulos com o mesmo nome de função ou de regra impedem a subida; uma transação chama `[:"ledger/post", dados]` e o transactor resolve pelo registro. *Sprint:* s01 (mecanismo), s02 (funções), s03 (regras).

**R25. Pontos de extensão** (D24). O e01 entrega o behaviour `Enoch.Storage`, os metadados do schema legíveis por outros módulos e a suíte de contrato como módulo reutilizável em `lib/` (por exemplo `use Enoch.Storage.ContractCase`). Uma extensão interna é dependência opcional dentro do pacote `enoch`; uma externa é um pacote separado que implementa os mesmos behaviours; os nomes de módulo não mudam entre as duas formas. *Aceite:* um adaptador de teste fora de `lib/enoch/adapters` roda a suíte de contrato; um módulo externo lê os metadados do schema depois de instalado. *Sprint:* s01 (behaviour e suíte), s02 (metadados do schema).

### Consulta

**R26. Avaliador** (D6, D9, D10, D33). Cláusulas, joins, predicados, agregados (`count`, `sum`, `min`, `max`), regras nomeadas não recursivas, `get-else`, `missing?`, predicados de função `[(op ?x ...)]`, `or`, `or-join`, `not` e `not-join`; as formas de `:find` escalar e de coleção e `:in` com parâmetros entram no avaliador (item 36(e) de `decisoes.md`, fechado em D33). *Aceite:* a suíte cobre cada cláusula; o resultado é o mesmo nos dois adaptadores; um agregado sobre `:decimal` soma inteiros e devolve `Decimal`. *Sprint:* s03.

**R27. `as_of`, `:history` e tempo** (D5, D28, D33, D16). `as_of` por `t` e por data (resolvida para um `t` pelo `txInstant`); o instante da transação (`:db/txInstant`) é consultável; a base `:history` devolve afirmações e retrações com `tx` e `added`. [PROPOSTA] Entidade e `pull` sobre `:history` devolvem erro explícito, porque há vários valores para o mesmo fato (D28 manda a spec definir). *Aceite:* `as_of` por data resolve o mesmo `t` que `as_of` por `t`; `:history` devolve a retração; um `pull` sobre `:history` devolve erro explícito. *Sprint:* s03.

**R28. `pull` e `scan`** (D5, D33, D7). `pull` por nível do padrão; um invólucro público do `scan` do `Enoch.Storage` para acesso direto aos índices, equivalente a `d/datoms`. *Aceite:* `pull` devolve o padrão pedido; o invólucro devolve os mesmos datoms da varredura. *Sprint:* s03.

### Dados derivados

**R29. Dados derivados** (D30, D39). Um valor derivado nunca é fonte de verdade: é reconstruível a partir do log e verificável contra o recálculo. O e01 entrega leitura por regras nomeadas e agregados, `Enoch.verify_derived` (compara o valor gravado com o recálculo e aponta divergências; também uma opção de subida, desligada por padrão) e, por D39, a manutenção automática de atributo derivado declarado no schema, escrita pelo motor na mesma transação. A D39 revoga em parte a D30, que mandava essa manutenção para o e02; os assinantes de eventos continuam no e02 (F7). *Aceite:* `verify_derived` aponta um valor adulterado; um atributo derivado declarado no schema é atualizado na mesma transação que muda os fatos e igual ao recálculo; reconstruir a partir do log reproduz o valor. *Sprint:* leitura e `verify_derived` na s03; a manutenção automática na s05, conforme a proposta P1 (D39 deixa a sprint para a spec).

### API e subida

**R30. API pública funcional** (D32). O núcleo recebe o nome da instância (`Enoch.start_link(name: ..., adapter: ..., schema: [...])`, `Enoch.transact(nome, dados)`); `use Enoch.Repo` é uma camada fina que delega ao núcleo; a API do e01 expõe `transact`, `q`, `pull`, `db`, `as_of` e `history`; cada instância sobe uma árvore de supervisão própria com o processo dono das tabelas, o transactor e a admissão. O registro de extensões do e02 (F5) não pode ser impedido por esta API: as listas `schema:`, `functions:` e `rules:` aceitam módulos de qualquer origem. *Aceite:* duas instâncias com nomes diferentes convivem no mesmo nó sem compartilhar estado; um `Enoch.Repo` e uma chamada funcional dão o mesmo resultado; `:memory:` por teste não exige módulo próprio; uma instância sobe com módulos de schema, de funções e de regras definidos fora do pacote. *Sprint:* s01 (esqueleto), s02 e s03 (`transact`, `q`, `pull`, `as_of` e `history` à medida que passam a existir).

**R31. Sequência de subida** (D34, D30). Os sete passos: abrir o storage e conferir a versão do layout (recusar layout mais novo); conferir estado atual contra o log e reconstruir se divergir; iniciar o transactor com a admissão fechada; registrar funções e regras; instalar o schema; aplicar migrações pendentes; abrir a admissão e emitir a telemetria. Uma falha em qualquer passo impede a subida, com erro explícito e admissão fechada. Não há gancho de subida para a aplicação; o app de exemplo documenta o padrão (dados iniciais por upsert, reconciliador como processo supervisionado). A versão do layout é um método do contrato `Enoch.Storage`; o `Memory` não a persiste. [PROPOSTA] No SQLite a versão do layout fica em `PRAGMA user_version` (D34: "por exemplo"; não verificado). *Aceite:* um layout mais novo impede a subida; um estado atual adulterado é reconstruído na subida; um schema incompatível impede a subida com a admissão fechada. *Sprint:* s01 (passos 1, 2, 3 e 7 e o mecanismo do passo 4), s02 (funções no passo 4 e o passo 5), s03 (regras no passo 4), s04 (versão no SQLite), s05 (passo 6).

**R32. Divergência entre índice e transactor, e conferência do `t`** (D42). Direção do dono: evitar que o índice único parcial e o transactor divirjam e, se divergirem, valer o valor mais novo; conferir o último `t` lido pelo SQLite e ter uma forma de validar qual é o correto. O mecanismo é proposta do agente, a confirmar: índice criado pelo instalador e gravado na mesma transação do transactor; conferência no passo 2 da subida; o `max(tx)` do log é o `t` autoritativo e o estado atual é reconstruído a partir do log. *Aceite:* o teste fabrica um índice divergente e a subida o detecta; um `t` divergente leva à reconstrução do estado atual. *Sprint:* s04 (atribuição do agente, a confirmar; a D22 não a atribui). O sentido de "mais novo" está na proposta P2.

### Stack, empacotamento e processo

**R33. Pacote e toolchain** (D23, D37, D38). Um único pacote `enoch`, app OTP `:enoch`, módulos sob `Enoch`; adaptadores como módulos; driver `exqlite`; Elixir 1.20.4 e OTP 29; piso `~> 1.20` (iniciativa do agente aceita junto com o conjunto); `decimal ~> 3.2`, `telemetry ~> 1.0`, ExUnit e `stream_data ~> 1.0` só em teste. *Aceite:* `mix deps.get`, `mix compile` e `mix test` passam com Elixir 1.20.4 e OTP 29; `mix hex.audit` não acusa avisos. *Sprint:* s01.

**R34. Flake, contêiner e SQLite embutido** (D38, D40). O flake fixa `beam.packages.erlang_29.elixir_1_20` e serve para chamar (`nix run .#test`, `nix run .#estado`, `nix flake check`, pacote da imagem); o `devShell` continua. O `Dockerfile` usa dois estágios sobre Alpine. O SQLite fica embutido no contêiner do back, sem volume externo obrigatório, e o dono quer poder desabilitá-lo, se possível. [PROPOSTA] A seleção já existe na opção `adapter:` (R30): desabilitar o SQLite é subir com o `Memory`, e `exqlite` entra como dependência opcional do pacote. [PROPOSTA] A imagem construída pelo flake, sem Docker, que a D38 manda avaliar na spec, não foi avaliada; fica como item de avaliação da s05 e o `Dockerfile` é o caminho especificado. *Aceite:* os comandos do flake rodam; o contêiner sobe e um `Enoch.transact` seguido de `q` devolve o dado gravado, com o SQLite embutido. *Sprint:* a D22 não atribui o flake nem o `Dockerfile`; a proposta do agente, a confirmar, é o flake na s01 e o `Dockerfile` com o exemplo na s05. Não verificados e a verificar na s05: o NIF pré-compilado em Alpine (`aarch64` e `x86_64`), o `mix release` na imagem enxuta e o modo WAL em arquivo sob musl.

**R35. Vocabulário e árvore** (D25, D41, D38). Os termos Aplicação e Extensão (com os três tipos) e o restante do vocabulário estão em `CONTEXT.md`; para o Transactor, "escritor" é aceito e "writer" é vetado; a árvore de pastas está em `docs/arquitetura.md`, cada pasta com um `CONTEXT.md`. *Aceite:* a revisão (`06_review`) não encontra o termo vetado "writer" em `lib/`, `test/` e `docs/`; cada pasta da árvore tem `CONTEXT.md` (verificável por listagem). *Sprint:* transversal.

**R36. Tracker e processo** (D38). O tracker é o GitHub Issues do repositório `CaioFaSoares/EnochDB`; o registro de uso está em `docs/agents/README.md`. *Aceite:* cada issue da `04_tickets` aponta para esta spec pelo caminho, sem copiá-la. *Sprint:* transversal.

### Critério de aceite do e01

**R37. Fechamento do e01** (D17, D22). O e01 só fecha com os quatro itens. (1) Uma suíte de contrato única, rodando nos dois adaptadores, cobrindo visibilidade, `as_of`, unicidade, ordem e normalização do `:decimal`, tempids e lookup refs (R2, R3, R9, R11, R18, R19). (2) Um app de exemplo que declara um schema com `:decimal`, faz `transact` com tempids, lookup refs, `cas` e metadados de transação e consulta com `q` (agregado e regra não recursiva), `pull` e `as_of`; mostra a evolução do schema da versão 1 para a 2 (R22, R23); e documenta o padrão de dados iniciais por upsert e reconciliador supervisionado (R31). (3) O custo do presente independe do histórico, nos dois adaptadores (R6). (4) Persistência do SQLite em arquivo (R7). *Aceite:* os quatro itens passam em `mix test` e no exemplo. *Sprint:* s05 fecha o item 2; os demais fecham em s01 a s04.

## Critérios de aceite da s01

Lista que o gate `tickets` e o `/icm implement` leem. Cada item é o aceite de um requisito da s01, sem texto novo; os critérios das sprints s02 a s05 entram aqui quando os tickets delas forem planejados.

- [ ] R1: nenhum callback do `Enoch.Storage` recebe uma consulta Datalog, e a suíte de contrato roda as varreduras e o pushdown no `Memory`.
- [ ] R2: afirmar, retrair e reafirmar o mesmo `(e, a, v)` deixa três linhas no histórico e um datom no estado atual, e o estado atual reconstruído do histórico é idêntico ao gravado, no `Memory`.
- [ ] R4: um teste de leitura concorrente com escrita contínua termina e é consistente com a base, e um banco de base `L` com a transação `L+1` completa antes da varredura lê consistente com `L`.
- [ ] R5: o teste "queda no meio da escrita", com leitor em curso durante a recuperação, passa no `Memory` e confere que o contador de admissão volta a zero.
- [ ] R6: uma consulta ao presente lê o mesmo número de linhas antes e depois de N retrações, no `Memory`.
- [ ] R16 (parte da s01): o `Memory` exige a opção `max_memory`, aceita `:infinity` e não sobe sem ela.
- [ ] R8: o Anexo A existe e cobre as varreduras e a leitura do último `t`.
- [ ] R11: `add` e `retract` crus gravam e são lidos de volta pelo `Memory`.
- [ ] R13: acima do limite o chamador recebe rejeição explícita, com a admissão fechada uma escrita externa é rejeitada, e depois da queda do transactor o contador de admissão volta a zero.
- [ ] R17: a subida emite um evento `:telemetry` com a base, e o contador de linhas lidas por varredura está exposto.
- [ ] R24: dois módulos que registram o mesmo nome de função ou de regra impedem a subida.
- [ ] R25: um adaptador de teste fora de `lib/enoch/adapters` roda a suíte de contrato.
- [ ] R30: duas instâncias com nomes diferentes não compartilham estado, um `Enoch.Repo` e a chamada funcional dão o mesmo resultado, e uma instância sobe com módulos de schema, funções e regras definidos fora do pacote.
- [ ] R31: um layout mais novo impede a subida e um estado atual adulterado é reconstruído na subida.
- [ ] R33: `mix deps.get`, `mix compile` e `mix test` passam com Elixir 1.20.4 e OTP 29, e `mix hex.audit` não acusa avisos.
- [ ] R34: o flake fixa `beam.packages.erlang_29.elixir_1_20` e `nix run .#test`, `nix run .#estado` e `nix flake check` rodam.
- [ ] R35 e R36: cada pasta da árvore tem `CONTEXT.md` e cada issue aponta para esta spec pelo caminho.

## Fora de escopo

- **F1. e02 e e03** (D1). MySQL, Postgres, Absinthe, Ash, Litestream, corrente de hashes, excisão e regras recursivas ficam no e02; o ledger e o domínio financeiro, no e03. Os agregados vieram para o e01 (D9) e a base `:history` também (D28).
- **F2. Obol** (D2, D23). O primeiro cliente real é o Obol, e a reescrita só começa no e03; o Obol não entra no e01 nem no e02.
- **F3. Eventos de transação** (D5). O `listen/1` e os eventos de transação (PubSub) ficam no e02; o `:history` foi para o e01 (D28).
- **F4. Regras recursivas** (D9, D10). Avaliação semi-naive, estratificação e terminação ficam no e02; as regras nomeadas não recursivas estão no e01 (R26).
- **F5. Registro e descoberta de extensões** (D24). Ficam no e02; o e01 só entrega os pontos de extensão (R25).
- **F6. Group commit e escrita em paralelo** (D27). `transact_async` com várias transações em andamento e pipeline ficam para depois da medição (R14); a opção sem histórico por atributo precisa de decisão própria porque conflita com o log imutável (R2).
- **F7. Assinantes de eventos** (D30, D39). A opção D de dados derivados fica no e02.
- **F8. Componentes e navegação por entidade** (D33). `:db/isComponent` com retração em cascata, `pull` dos componentes e `d/entity` ficam no e02; `d/sync` só importa com vários nós.
- **F9. Tipos não suportados** (D36). `:double`, `:bytes` e `:uri`.
- **F10. Geradores e ensaio** (D38, D29). Sem geradores no e01; a tarefa de ensaio da instalação segue o item 31.
- **F11. Compilador de Datalog para SQL e linhas com intervalo de visibilidade** (D6, D15, D16). Descartados.

## Propostas e pendências do dono

Onde uma decisão delegou o valor à spec (D21, D26, D27, D28, D29, D34, D36, D39, D40, D42), a spec propõe, e cada [PROPOSTA] só vale depois do gate humano. As propostas já estão nos requisitos R13, R16, R19, R22, R27, R31 e R34; as demais:

- **P1. Opção C, derivados mantidos pelo motor** (D39). [PROPOSTA] Sprint s05, depois de `verify_derived` (s03), porque depende do schema (s02), das regras (s03) e da escrita na mesma transação; o exemplo da s05 mostra um saldo derivado. Corte: agregados simples (`count`, `sum`) por delta e recálculo das entidades afetadas para o resto. `verify_derived` segue opcional e desligado por padrão (D30, D34).
- **P2. Divergência entre índice e transactor, e `t` do SQLite** (D42). [PROPOSTA] "Mais novo" é o fato da transação de maior `tx` no log. O estado atual e o índice são derivados do log; quando divergem, são reconstruídos a partir do log e prevalece o valor da maior `tx`. O índice único parcial nunca decide a regra: se rejeitar o que o transactor aceitou, a transação é revertida com erro explícito (D14). O `max(tx)` do log é o `t` autoritativo do SQLite. O dono confirma essa leitura de "mais novo".
- **P3. `immutable`** (D26). [PROPOSTA] O atributo é imutável a partir da transação que o afirma, e dentro dela vale o conflito normal de cardinalidade; a excisão (e02) é a única exceção possível e exige decisão própria; a opção sem histórico conflita com o log imutável e exige decisão própria (R2, F6).
- **P4. Ensaio da instalação** (D29). [PROPOSTA] Fora do e01, junto com os geradores (F10), porque o item 31 só fechou os geradores e a spec não acrescenta escopo.

## Seams de verificação

Não há seams existentes: o repositório não tem código. Os seams são os que as decisões já exigem, e nenhum é novo.

- A suíte de contrato `Enoch.Storage.ContractCase` (D17, D24), executada nos dois adaptadores.
- O contador de linhas lidas por varredura (D17, D18).
- Os eventos de telemetria (D21, D27).
- O app de exemplo da s05 (D17, D38).
- O instalador e `Enoch.verify_derived` como pontos de verificação do schema e dos derivados (D29, D30).

## Cobertura das decisões

| Decisão | Requisito |
| --- | --- |
| D1 | F1 |
| D2 | F2 |
| D5 | R11, R27, R28, F3 |
| D6 | R1, R26, F11 |
| D7 | R1, R28 |
| D8 | R3 |
| D9 | R26, F4 |
| D10 | R26, F4 |
| D11 | R11 |
| D12 | R18 |
| D13 | R18 |
| D14 | R9 |
| D15 (superada por D16) | R1, R2, F11 |
| D16 | R2, R3, R7, F11 |
| D17 | R6, R7, R37 |
| D18 | R4, R5, R6 |
| D19 | R15 |
| D20 | R16 |
| D21 | R5, R12, R15, R16, R17 |
| D22 | Escopo por sprint, R8, R37 |
| D23 | R33, F2 |
| D24 | R24, R25, F5 |
| D25 | R35 |
| D26 | R10 |
| D27 | R12, R13, R14, R17, F6 |
| D28 | R3, R27 |
| D29 | R22, R23, F10, P4 |
| D30 | R29, F7 |
| D31 | R21 |
| D32 | R30 |
| D33 | R10, R11, R26, R27, R28, F8 |
| D34 | R13, R17, R31 |
| D35 | R12, R24 |
| D36 | R19, R20, F9 |
| D37 | R18, R33 |
| D38 | R18, R33, R34, R35, R36, F10 |
| D39 | R29, P1, Escopo por sprint |
| D40 | R34 |
| D41 | R35 |
| D42 | R32, P2 |

## Anexo A — Consultas e índices do SQLite, no papel (R8)

[INFERÊNCIA] Desenho escrito sem execução, a confirmar na s04. O único fato executado é o teste de fumaça da D23: `exqlite` 0.42.0 com `STRICT, WITHOUT ROWID`, coluna `ANY`, índice parcial e `PRAGMA journal_mode = WAL`.

**Tabelas.** `datoms_log(e INTEGER, a INTEGER, v ANY, tx INTEGER, added INTEGER)`, só `INSERT`, com gatilhos que recusam `UPDATE` e `DELETE`. `datoms(e INTEGER, a INTEGER, v ANY)` é o estado atual. Valores por tipo: `:long`, `:decimal` (inteiro escalado), `:instant` (microssegundos), `:ref` e `:boolean` (0 e 1) como inteiro; `:string` e `:keyword` como texto em UTF-8; `:uuid` como `BLOB` de 16 bytes. Como cada atributo tem um único tipo (R20), a ordem de `v` dentro de uma varredura por atributo é a do SQLite com a collation binária, que coincide com a ordem definida em R19; a ordem entre classes de armazenamento nunca é usada.

**Índices covering do log.** EAVT `(e, a, v, tx, added)`, AEVT `(a, e, v, tx, added)`, AVET `(a, v, e, tx, added)` só para atributos indexados e VAET `(v, a, e, tx, added)` só para `:ref`. O estado atual tem os mesmos quatro índices, sem `tx` e `added`.

**Varreduras com pushdown** (R1, R3). As quatro varreduras do contrato, cada uma com a forma do presente (lê `datoms`) e a do passado e `:history` (lê `datoms_log`, com `AND tx <= ?b` e `ORDER BY` terminando em `tx`, de modo que as linhas do mesmo `(e, a, v)` cheguem adjacentes e ordenadas por `tx`; para `:history` sem filtro de tempo omite-se `tx <= ?b`):

| Varredura | Presente | Passado e `:history` |
| --- | --- | --- |
| EAVT, por entidade (e opcionalmente atributo) | `SELECT a, v FROM datoms WHERE e = ?1 [AND a = ?2]` | `SELECT a, v, tx, added FROM datoms_log WHERE e = ?1 [AND a = ?2] AND tx <= ?b ORDER BY a, v, tx` |
| AEVT, por atributo | `SELECT e, v FROM datoms WHERE a = ?1 ORDER BY e` | `SELECT e, v, tx, added FROM datoms_log WHERE a = ?1 AND tx <= ?b ORDER BY e, v, tx` |
| AVET, por atributo e valor ou faixa (atributos indexados) | `SELECT e FROM datoms WHERE a = ?1 AND v BETWEEN ?2 AND ?3` | `SELECT e, v, tx, added FROM datoms_log WHERE a = ?1 AND v BETWEEN ?2 AND ?3 AND tx <= ?b ORDER BY e, v, tx` |
| VAET, por valor referência (só `:ref`) | `SELECT e, a FROM datoms WHERE v = ?1` | `SELECT e, a, tx, added FROM datoms_log WHERE v = ?1 AND tx <= ?b ORDER BY e, a, tx` |

**Consistência da leitura** (item 23, D38). Uma transação de leitura por consulta, numa só conexão: dentro dela, `SELECT max(tx) FROM datoms_log` dá o último `t`; se a base do `db` é igual a ele, a varredura lê `datoms`; se é menor, lê `datoms_log` com `tx <= base`.
