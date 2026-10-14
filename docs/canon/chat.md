Desenvolvi recentemente um projeto em Clojure com Datomic + Datalog que me interessou bastante. a ideia de ter um schema direto em Clojure que é gerado na base de dados e os dados e visualizações podem ser puxados ou criados a partir de uma base transacional me interessa bastante, mas quao pesado o sistema é é algo que eu tenho encontrado como uma dificuldade. 

Pensei recriar o comportamento em Elixir e ao inves de postgres para guardar as transacoes, usar algo como SQLite, e queria entender como poderiamos fazer para replicar esse comportamento de forma clara, eficiente, mais leve, e plug and play para serviços menores que nao justificam todo um sistema de postgres para rodar sua base de dados, algo como uma base de dados customizavel que permita eu rapidamente preparar tudo que preciso para ter algo tao robusto quanto clojure e datalog mas com um footprint de performance muito menor para projetos pequenos.

querendo entender o necessário para fazer isso acontecer. minha ideia seria BEAM e SQLite, conseguir criar os schemas direto em Elixir e rapidinho integrar uma API, um middleware, GraphQL ou oq seja.

quais seriam os passos, precoupações e como fazemos isso acontecer?

--

Dá para fazer, e BEAM + SQLite combina bem com o modelo do Datomic. O Datomic já tem um único escritor (o transactor) e muitos leitores. O SQLite tem a mesma restrição: um escritor por vez e leitores concorrentes em modo WAL. No Elixir, um GenServer serializando as escritas faz o papel do transactor de forma natural. A seguir: o que você precisa replicar, como modelar cada parte e onde estão as armadilhas.

## O que o Datomic realmente te dá

Antes de construir, separe o que te atraiu do que é implementação. O núcleo conceitual é pequeno:

1. **Datoms.** Tudo é um fato `[entidade atributo valor transação adicionado?]`.
2. **Acréscimo, não sobrescrita.** Mudar um valor é retrair o antigo e afirmar o novo.
3. **Schema como dado.** Atributos são entidades, com tipo, cardinalidade e unicidade.
4. **Índices EAVT, AEVT, AVET e VAET.** Cada padrão de consulta tem um índice.
5. **Banco como valor.** Uma consulta roda contra o banco num instante `t`.
6. **Funções de transação** (`:db/cas`, por exemplo).
7. **Datalog e pull** como linguagens de leitura.

O peso que você sentiu vem quase todo da JVM, do processo transactor separado, do storage externo e do cache de índices no peer. Nada disso é essencial ao modelo.

Uma verificação rápida antes de reescrever: o Datomic Local e o Datalevin (Clojure sobre LMDB) são bem mais leves que o Datomic Pro com Postgres. Se o problema for só a infraestrutura, isso pode bastar. Se o objetivo é sair da JVM e ter algo nativo no BEAM, siga em frente.

## Armazenamento: o desenho das tabelas

A decisão mais importante é guardar **duas estruturas**: um log imutável, que é o histórico, e uma tabela de estado atual. As duas são atualizadas na mesma transação SQL. O Datomic faz algo análogo com índices de histórico e de estado atual. Sem a tabela atual, toda consulta precisaria reconstruir o presente a partir do log, o que é lento.

```sql
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;

CREATE TABLE tx (
  t       INTEGER PRIMARY KEY,
  instant INTEGER NOT NULL
);

-- histórico imutável: nunca recebe UPDATE nem DELETE
CREATE TABLE datoms_log (
  e INTEGER NOT NULL, a INTEGER NOT NULL, v ANY,
  tx INTEGER NOT NULL, added INTEGER NOT NULL
) STRICT;
CREATE INDEX log_eavt ON datoms_log(e, a, tx);
CREATE INDEX log_aevt ON datoms_log(a, e, tx);

-- estado atual; a chave primária clusterizada é o EAVT
CREATE TABLE datoms (
  e INTEGER NOT NULL, a INTEGER NOT NULL, v ANY NOT NULL, tx INTEGER NOT NULL,
  indexed INTEGER NOT NULL DEFAULT 0,  -- atributo com :index ou :unique
  is_ref  INTEGER NOT NULL DEFAULT 0,  -- atributo do tipo :ref
  uniq    INTEGER NOT NULL DEFAULT 0,  -- atributo com :unique
  PRIMARY KEY (e, a, v)
) STRICT, WITHOUT ROWID;

CREATE INDEX aevt ON datoms(a, e, v);
CREATE INDEX avet ON datoms(a, v, e) WHERE indexed = 1;
CREATE INDEX vaet ON datoms(v, a, e) WHERE is_ref = 1;
CREATE UNIQUE INDEX unique_av ON datoms(a, v) WHERE uniq = 1;
```

Alguns detalhes desse desenho fazem diferença:

- **`WITHOUT ROWID` com chave `(e, a, v)`.** A tabela vira o próprio índice EAVT.
- **Índices parciais.** Reproduzem o comportamento do Datomic, em que AVET e VAET só existem para atributos que pedem isso.
- **Índice único parcial.** O próprio SQLite garante `:db.unique`.
- **Tabelas `STRICT` com coluna `ANY`.** Guardam o valor com seu tipo nativo. Mesmo assim, o tipo real deve vir do schema do atributo, porque o SQLite compara tipos diferentes de forma peculiar (`'10'` não é igual a `10`).
- **Atributos como inteiros.** Os atributos são entidades. O nome `:person/name` vira um id, que você mantém em cache.

Para consultas "as of" e de histórico, o compilador de queries troca a fonte `datoms` por uma CTE sobre o log:

```sql
WITH db_at AS (
  SELECT e, a, v FROM (
    SELECT e, a, v, added,
           ROW_NUMBER() OVER (PARTITION BY e, a, v ORDER BY tx DESC) AS rn
    FROM datoms_log WHERE tx <= :t
  ) WHERE rn = 1 AND added = 1
)
SELECT ...
```

É mais caro, mas é exatamente o caso de uso de auditoria. O caminho quente continua na tabela atual.

## Schema em Elixir

Uma macro DSL em tempo de compilação resolve isso bem:

```elixir
defmodule MyApp.Schema do
  use Fato.Schema

  entity :person do
    attr :name,    :string, unique: :identity
    attr :email,   :string, unique: :value
    attr :age,     :long,   index: true
    attr :friends, :ref,    cardinality: :many
  end
end
```

Essa macro gera os atributos `person/name`, `person/email` e assim por diante, como dados. No boot, `Fato.Schema.install!/1` compara com o schema já gravado (que também é datom) e transaciona só o que é novo. Como o modelo é EAV, **não existem migrations de tabela**. A evolução de schema é aditiva, igual ao Datomic.

Você precisa de um bootstrap fixo com os atributos meta: `:db/ident`, `:db/valueType`, `:db/cardinality`, `:db/unique` e `:db/index`.

A mesma macro pode gerar outras coisas úteis:

- **Structs e typespecs** para os resultados de pull.
- **Validação em tempo de compilação.** Por exemplo, um `:ref` apontando para algo inexistente vira erro de compilação.
- **Metadados para gerar tipos GraphQL** depois.

Um detalhe prático: `:person/name` não é um átomo válido em Elixir, porque é lido como divisão. Use `:"person/name"` na API de dados e esconda isso nas macros.

## O transactor

Um GenServer recebe os dados da transação e executa um pipeline:

1. **Expandir** mapas em operações `[:add | :retract, e, a, v]`.
2. **Resolver** tempids e lookup refs (`[:"person/email", "x@y.com"]`).
3. **Aplicar a semântica do schema.** Num atributo de cardinalidade um, afirmar um valor novo gera automaticamente a retração do anterior.
4. **Rodar funções de transação** como `cas`.
5. **Validar tipos.**
6. **Gravar** log e estado atual numa única transação SQLite.

```elixir
defmodule Fato.Transactor do
  use GenServer

  def transact(tx_data), do: GenServer.call(__MODULE__, {:transact, tx_data}, 15_000)

  def handle_call({:transact, data}, _from, state) do
    with {:ok, ops}    <- Fato.Tx.expand(data, state.schema),
         {:ok, ops}    <- Fato.Tx.resolve(ops, state.conn, state.schema),
         {:ok, report} <- Fato.Store.write(state.conn, ops, state.next_t) do
      Phoenix.PubSub.broadcast(Fato.PubSub, "fato:tx", {:tx, report})
      {:reply, {:ok, report}, %{state | next_t: state.next_t + 1}}
    else
      error -> {:reply, error, state}
    end
  end
end
```

O broadcast é o seu `tx-report-queue`, e é aqui que o BEAM brilha. LiveViews e processos podem assinar as transações e reagir só aos atributos que interessam. É reatividade quase de graça.

Se o throughput apertar, adicione **group commit**: acumular várias chamadas em poucos milissegundos e gravar numa transação SQLite só.

## Datalog: o maior pedaço de trabalho

Existem dois caminhos. O que eu recomendo para começar é **compilar Datalog para SQL**. Cada cláusula vira um alias da tabela `datoms`, e variáveis compartilhadas viram condições de join:

```elixir
Fato.q(db,
  find:  [:name],
  where: [
    {:e, :"person/age", :age},
    {:>, :age, 30},
    {:e, :"person/name", :name}
  ])
```

```sql
SELECT d2.v AS name
FROM datoms d1
JOIN datoms d2 ON d2.e = d1.e AND d2.a = :attr_name
WHERE d1.a = :attr_age AND d1.v > 30
```

O resto da linguagem também tem tradução direta:

- **Predicados e agregados** viram SQL comum.
- **Regras recursivas** viram `WITH RECURSIVE`.
- **Pull** é uma camada separada que faz consultas em lote por nível do padrão, como `[:name {:friends [:name]}]`. Use um `WHERE e IN (...)` por nível para evitar N+1.

Assim você aproveita o planner do SQLite em vez de escrever um otimizador de joins.

O caminho alternativo é um avaliador em memória escrito em Elixir, com hash joins sobre varreduras de índice, no estilo do Datascript. Ele te dá mais controle e permite rodar Datalog sobre coleções arbitrárias, mas é muito mais código. Vale como uma fase posterior, se precisar.

Uma referência valiosa: o **Mozilla Mentat** era exatamente "Datomic-like sobre SQLite", em Rust. O projeto está arquivado, mas o desenho de tabelas e o compilador de Datalog para SQL dele valem estudo. Para o motor em memória, o código do **Datascript** é a referência clássica. Confirme os detalhes desses projetos direto nos repositórios, porque estou citando de memória.

## Banco como valor

`Fato.db()` retorna algo como `%Fato.Db{basis_t: 1042}`. Para consultas no presente, há duas opções:

- **Abrir uma transação de leitura no SQLite.** Em WAL ela já é um snapshot consistente. Funciona se você mantiver a mesma conexão durante as várias queries de uma operação.
- **Filtrar por `tx <= basis_t`.** Isso dá consistência mesmo entre conexões diferentes.

Os leitores ficam num pool separado da conexão de escrita. O `exqlite` (base do `ecto_sqlite3`) usa NIF em dirty schedulers, então não trava o BEAM.

## Integração com API e GraphQL

Como o schema é dado, quase tudo pode ser derivado dele:

- **GraphQL com Absinthe.** Os tipos saem dos namespaces de atributo, e a seleção do GraphQL é traduzida diretamente para um padrão de pull. Os dois são praticamente o mesmo conceito.
- **API REST** com Plug ou Phoenix, usando pull e transact como endpoints genéricos.
- **Ash Framework**, se quiser ir além: implementar um data layer customizado para o Ash. Você ganharia autorização, APIs e admin prontos em cima do seu armazenamento.

## Preocupações reais

- **Performance de EAV.** Muitos self-joins em queries com vários atributos. A tabela clusterizada e os índices de cobertura resolvem a maior parte. Rode `ANALYZE` periodicamente e confira os planos com `EXPLAIN QUERY PLAN`.
- **Crescimento do log.** Planeje cedo uma forma de "excision" (apagar dados de verdade, por LGPD) e de compactação.
- **Single node.** O SQLite vive numa máquina. Para backup contínuo e réplica em S3, use o **Litestream**, que se encaixa perfeitamente no seu cenário de "serviço pequeno plug and play".
- **Ids de entidade.** Use um contador alocado pelo transactor. Se quiser ids estáveis entre ambientes, use um atributo `:db/uuid` único.
- **Busca textual.** O FTS5 do SQLite resolve, alimentado pelo transactor para os atributos marcados como `fulltext: true`.
- **Testes.** SQLite `:memory:` por teste torna a suíte rápida e isolada.

## Ordem sugerida de construção

1. **Tabelas e transactor**, só com `add` e `retract` crus.
2. **Bootstrap do schema e a DSL**, com cardinalidade, unicidade e validação de tipos.
3. **Pull e Datalog básico** compilado para SQL: cláusulas, joins e predicados.
4. **Tempids, lookup refs, funções de transação e PubSub.**
5. **As-of e histórico, agregados e regras recursivas.**
6. **Integrações**: Absinthe, endpoints genéricos e Litestream.

As fases 1 a 3 já te dão algo usável num fim de semana longo. A fase 5 é onde mora a maior parte da complexidade.

Quer que eu comece pela fase 1 e escreva o módulo de storage com o transactor funcionando, ou prefere detalhar primeiro o compilador de Datalog para SQL?

--

quero entender a topologia do código, como seria o beam completo + algo como transactor + mysql e quais regioes arquiteturais teriamos que montar. 

parte do agradavel de conduzir o desenvolvimento do framework seria poder transformar isso em algo genério que possa ser usado de forma simples. ah tem um projeto que se beneficiaria de uma db transacional em ledger como um organizador financeiro? é uma boa escolha.

precisa de algo que ledger, auditoria, e afins sao necessários? é boa escolha, além de ser leve o suficiente pra poder ser embebido se precisar.

--

## Como isso vira código

O padrão que deixa tudo "plug and play" é o mesmo do Ecto. A aplicação do usuário define um repo próprio, e o framework sobe uma árvore de supervisão por repo. Isso permite várias bases na mesma app (uma por tenant, por exemplo), embutir em qualquer projeto e testar com o adaptador em memória.

```elixir
defmodule MyApp.Db do
  use Fato.Repo,
    otp_app: :my_app,
    adapter: Fato.Adapters.SQLite,
    schema: MyApp.Schema
end

# config/runtime.exs
config :my_app, MyApp.Db, path: "priv/data/app.db", readers: 4

# application.ex
children = [MyApp.Db]
```

O `use Fato.Repo` gera `transact/1`, `q/2`, `pull/3`, `db/0`, `as_of/1` e `listen/1` delegando ao núcleo. Por baixo, cada repo sobe esta árvore:

```
MyApp.Db (Supervisor, :rest_for_one)
├── Fato.Storage.Writer      # a única conexão de escrita
├── Fato.Storage.ReaderPool  # conexões só leitura
├── Fato.Schema.Registry     # carrega o schema e publica em persistent_term
├── Fato.Transactor          # GenServer serializando transações
└── Fato.Events              # Registry/PubSub com os tx reports
```

A estratégia `:rest_for_one` importa aqui. Se o writer cair, o transactor reinicia junto e relê o `basis_t` do banco, então nunca fica com estado defasado.

A organização de pastas espelha as regiões do diagrama:

```
fato/
├── lib/fato/
│   ├── repo.ex                  # macro use Fato.Repo
│   ├── db.ex                    # %Fato.Db{basis_t, repo} — o "banco como valor"
│   ├── schema/
│   │   ├── dsl.ex               # macros entity/attr
│   │   ├── bootstrap.ex         # atributos meta :db/*
│   │   ├── registry.ex          # cache em persistent_term
│   │   └── installer.ex         # diff e instalação aditiva
│   ├── tx/
│   │   ├── expand.ex            # mapas para [:add/:retract]
│   │   ├── resolve.ex           # tempids, lookup refs, cardinalidade
│   │   ├── functions.ex         # behaviour de funções de transação
│   │   ├── validate.ex          # tipos e invariantes
│   │   └── report.ex            # %TxReport{t, datoms, tempids}
│   ├── transactor.ex
│   ├── query/
│   │   ├── parser.ex            # Elixir para AST de Datalog
│   │   ├── planner.ex           # ordem de cláusulas, bindings
│   │   ├── compiler.ex          # AST para SQL via dialeto
│   │   ├── rules.ex             # regras para WITH RECURSIVE
│   │   └── pull.ex
│   ├── storage/
│   │   ├── storage.ex           # behaviour
│   │   └── dialect.ex           # behaviour de SQL por banco
│   └── events.ex
└── lib/fato/adapters/
    ├── sqlite.ex
    ├── mysql.ex
    ├── postgres.ex
    └── memory.ex                # ETS, para testes e protótipos
```

## A fronteira do adaptador

O ponto mais delicado do design é escolher onde fica essa fronteira. O núcleo produz um AST de consulta e uma lista de operações de escrita. O adaptador decide como isso vira SQL e como os datoms são guardados.

```elixir
defmodule Fato.Storage do
  @callback init(opts :: keyword) :: {:ok, state} | {:error, term}
  @callback bootstrap(state) :: :ok
  @callback basis_t(state) :: non_neg_integer
  @callback write_tx(state, t :: pos_integer, ops :: [op], meta :: map) :: :ok | {:error, term}
  @callback compile(query_ast :: Fato.Query.AST.t(), source :: :current | {:as_of, t} | :history) ::
              {sql :: iodata, params :: list}
  @callback run(state, sql :: iodata, params :: list) :: {:ok, rows} | {:error, term}
end
```

O MySQL mostra por que o layout físico precisa ser do adaptador, e não do núcleo. Três coisas do desenho com SQLite não existem lá:

- **Índices parciais.** O MySQL não tem. O AVET seletivo vira tabelas separadas, ou um índice sobre colunas geradas.
- **Coluna de tipo dinâmico.** Não existe `ANY`. Você precisa de colunas tipadas (`v_long`, `v_str`, `v_ref`, `v_dec`, `v_inst`) ou de uma tabela por tipo de valor. Esta segunda opção é a mais limpa, e o Datomic faz algo parecido internamente.
- **Unicidade parcial.** Sem índice único parcial, o adaptador implementa a unicidade com uma tabela `unique_av` só com os atributos únicos.

Por outro lado, o MySQL 8 tem window functions e `WITH RECURSIVE`, então as-of e regras recursivas funcionam. Por isso o compilador tem um núcleo comum e um módulo de dialeto por banco.

Existe ainda uma preocupação que só aparece com MySQL ou Postgres: **vários nós da aplicação**. Com SQLite embutido há um processo só e um transactor só. Com um banco de rede, cada nó subiria seu próprio transactor, e a garantia de escritor único quebra. Duas saídas:

- **Singleton no cluster**, com `:global` ou Horde.
- **Lock no banco** (`GET_LOCK` no MySQL, advisory lock no Postgres), que o transactor adquire no boot. Os outros nós encaminham as transações para quem tem o lock.

Comece com o lock no banco: é mais simples e não depende de cluster Erlang.

## O organizador financeiro é uma boa escolha?

É uma das melhores escolhas possíveis para esse modelo. Para um organizador pessoal ou de pequenos negócios, SQLite embutido é mais que suficiente: um usuário gera milhares de lançamentos por ano, não milhões por segundo.

Um ponto precisa ficar claro desde o início: **o histórico de datoms te dá auditoria de dados, mas não te dá um ledger**. Ele responde "quem mudou esse valor e quando". Um ledger financeiro exige mais semânticas por cima, e são elas que fazem o projeto dar certo.

### Partidas dobradas como função de transação

Cada lançamento debita e credita contas, e a soma das pernas tem que ser zero. Esse invariante precisa ser garantido dentro do transactor, porque assim é impossível gravar um lançamento desbalanceado:

```elixir
defmodule Ledger.TxFns.Post do
  @behaviour Fato.Tx.Function

  def call(_db, %{entry: entry, legs: legs}) do
    if Enum.sum(Enum.map(legs, & &1.amount)) == 0 do
      {:ok,
       [%{"db/id": "entry", "entry/memo": entry.memo, "entry/effective": entry.effective}] ++
         Enum.map(legs, &%{"leg/entry": "entry", "leg/account": &1.account, "leg/amount": &1.amount})}
    else
      {:error, :unbalanced}
    end
  end
end
```

### Dinheiro nunca como float

Guarde inteiros na menor unidade (centavos) e um atributo de moeda, ou um tipo `:decimal` no schema que o adaptador serializa como texto ou inteiro escalado. Inclua isso na DSL desde o primeiro dia.

### Duas noções de tempo

Essa é a armadilha mais comum. O Datomic é unitemporal: só conhece o momento em que o fato foi gravado. Em finanças você também precisa da data em que o fato vale. Um pagamento lançado hoje pode ter acontecido semana passada. Os dois tempos respondem perguntas diferentes:

- **Data efetiva** (`entry/effective`) responde "qual era meu saldo em 31/03?".
- **`as_of(t)` do sistema** responde "o que o sistema mostrava em 31/03, antes da correção?".

Ter as duas consultas é exatamente o que uma auditoria pede. Modele a data efetiva como atributo comum e deixe o `as_of` para o tempo de transação.

### Correções por estorno, nunca por edição

Num ledger, lançamento não se edita: se estorna e se lança de novo. O modelo de acréscimo do Datomic favorece isso naturalmente. Uma regra simples na função de transação garante: lançamentos são imutáveis depois de criados.

### Metadados na transação

O Datomic permite atributos na própria entidade da transação. Copie isso: `tx/user`, `tx/reason`, `tx/source` (importação de OFX, entrada manual, API). Assim, cada mudança carrega quem, por quê e de onde, sem tabela de auditoria paralela.

### Chave de idempotência

Importações de extrato e chamadas de API repetem. Um atributo `entry/external_id` com `unique: :identity` faz a mesma transação reenviada virar upsert, em vez de um lançamento duplicado.

### Evidência contra adulteração

Isso custa pouco e tem muito valor para auditoria. Cada linha de `tx` guarda o hash dos datoms dela mais o hash da transação anterior, formando uma corrente. No SQLite, gatilhos impedem alteração do log mesmo por quem abra o arquivo com outra ferramenta:

```sql
ALTER TABLE tx ADD COLUMN hash BLOB;
ALTER TABLE tx ADD COLUMN prev_hash BLOB;

CREATE TRIGGER log_no_update BEFORE UPDATE ON datoms_log
BEGIN SELECT RAISE(ABORT, 'datoms_log é imutável'); END;

CREATE TRIGGER log_no_delete BEFORE DELETE ON datoms_log
BEGIN SELECT RAISE(ABORT, 'datoms_log é imutável'); END;
```

Os gatilhos não impedem um atacante determinado. Mas a corrente de hashes permite detectar qualquer alteração: basta recalcular e comparar, ou publicar o hash mais recente periodicamente em outro lugar.

### A tensão com a LGPD

Imutabilidade total colide com o direito de exclusão. Planeje uma operação de **excisão** que remove os datoms pessoais de uma entidade e registra uma transação "excisão feita por X, motivo Y". Ela quebra a corrente de hashes de forma controlada e documentada. Dados financeiros em si costumam ter obrigação legal de guarda, então a excisão normalmente atinge dados pessoais, não os lançamentos.

### Saldos

Calcular saldo somando todas as pernas a cada consulta funciona por bastante tempo no SQLite. Quando ficar lento, mantenha uma projeção (`balance` por conta), atualizada pelo transactor na mesma transação ou por um assinante do event bus. Ela é sempre reconstruível a partir do log, então nunca vira fonte de verdade.

### Quando não é a escolha certa

O modelo para de servir em processamento de pagamentos de alto volume, com milhares de escritas por segundo e múltiplas regiões. Nesse cenário, o escritor único vira gargalo, e sistemas como TigerBeetle existem justamente para isso. Para um organizador financeiro, nem perto.

## Ordem de construção

O caminho que valida o framework mais cedo é construir os dois em paralelo, com o ledger como primeiro cliente real:

1. **Núcleo com SQLite e adaptador em memória.**
2. **Schema do ledger:** contas, lançamentos, pernas e moeda.
3. **A função `post`** com invariante de balanço.
4. **Importação idempotente.**
5. **As-of e data efetiva.**
6. **Corrente de hashes.**

Cada necessidade do ledger que for genérica (decimal, metadados de transação, imutabilidade por atributo, excisão) sobe para o framework. O que for de domínio fica na app. Deixe o adaptador MySQL para quando tudo isso estiver estável, porque ele vai testar se a fronteira do `Fato.Storage` ficou no lugar certo.

Quer que eu escreva o schema completo do ledger nessa DSL, com as funções de transação e as consultas de saldo em Datalog?

--

Faz sentido. O nome simbólico fica só na porta de entrada, e dentro do código cada módulo diz o que faz. Quem abrir o projeto daqui a seis meses (inclusive você) agradece.

```elixir
Enoch                        # o framework
Enoch.Repo                   # macro use Enoch.Repo
Enoch.Db                     # o banco como valor (%Enoch.Db{basis_t})
Enoch.Schema                 # DSL entity/attr
Enoch.Schema.Registry
Enoch.Transactor
Enoch.Tx.Expand
Enoch.Tx.Resolve
Enoch.Tx.Function            # behaviour das funções de transação
Enoch.Query                  # parser, planner e compilador Datalog
Enoch.Pull
Enoch.Events                 # tx reports e assinaturas
Enoch.Storage                # behaviour do adaptador
Enoch.Adapters.SQLite
Enoch.Adapters.MySQL
Enoch.Adapters.Memory

Thoth                        # o organizador financeiro
```

Os nomes seguem o vocabulário do Datomic e do Ecto (`Repo`, `Transactor`, `Pull`, `Adapters`). Assim quem conhece algum dos dois se orienta na hora. Se em algum momento um módulo ganhar identidade própria, virando um pacote separado, por exemplo, aí vale reconsiderar um nome simbólico para ele.

--

