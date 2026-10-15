defmodule Enoch.Storage do
  @moduledoc """
  Contrato do adaptador de storage: as varreduras dos índices, com pushdown mínimo.

  O adaptador oferece as quatro varreduras dos índices — EAVT, AEVT, AVET e VAET —
  e aplica antes de devolver as linhas os filtros de pushdown por atributo (`a`) e
  por valor (`v`); o filtro por tempo é a base do banco como valor, em
  `Enoch.DB`. Joins, regras e semântica ficam no avaliador: **nenhum callback
  recebe uma consulta Datalog e o contrato não tem `compile/2`** (D6, D7, R1).

  ## A base escolhe a varredura

  A varredura recebe o banco como valor — `{referências, basis_t}` (D18) — e
  devolve os datoms consistentes com a base:

  - **base igual ao último `t`**: lê o estado atual, sem custo de histórico. Os
    datoms vêm sem `tx` e sem `added`, porque o estado atual é a projeção dos
    datoms vivos e não guarda a transação que os afirmou;
  - **base anterior** (`basis_t` menor que o último `t` — o `{:as_of, t}` e o
    banco como valor antigo da D16): lê o histórico, com as linhas de afirmação e
    de retração. Os datoms vêm com `tx` e `added`, e as linhas do mesmo
    `(e, a, v)` chegam adjacentes e ordenadas por `tx`, para o avaliador resolver
    a visibilidade num só lugar (D8, D16).

  A escolha da base é a regra normal; o adaptador pode refazer uma varredura pelo
  histórico na mesma base quando detecta uma escrita concorrente no meio dela
  (D18). As linhas vêm, então, como as do histórico — com `tx` e `added` —, e a
  visibilidade continua sendo do avaliador.

  A base `:history`, sem filtro de tempo, não entra na s01 (D28).

  ## As quatro varreduras do Anexo A (R8)

  | Varredura do Anexo A | Callback | Pushdown obrigatório | Pushdown opcional |
  | --- | --- | --- | --- |
  | EAVT, por entidade | `c:scan_eavt/2` | `e` | `a` |
  | AEVT, por atributo | `c:scan_aevt/2` | `a` | `e` |
  | AVET, por atributo e valor ou faixa | `c:scan_avet/2` | `a` e (`v` ou `min_v`/`max_v`) | — |
  | VAET, por valor referência | `c:scan_vaet/2` | `v` | `a` |

  As varreduras devolvem o datom inteiro, e não só as colunas que o Anexo A
  projeta no SQLite; a ordem externa é a do índice do adaptador.

  As duas formas de cada varredura no Anexo A — a do presente, que lê `datoms`, e
  a do passado, que lê `datoms_log` com `tx <= ?b` — são a mesma varredura do
  contrato: o que escolhe entre elas é a base do banco como valor, não o callback.

  A base `:history`, sem filtro de tempo, não entra na s01 (D28).

  ## Linhas lidas por varredura

  `c:rows_read/1` expõe quantas linhas as varreduras leram desde `open/1` (D17,
  critério 3; R6). É a métrica determinística do custo do presente: a varredura
  pelo estado atual lê só os datoms vivos, então o presente lê o mesmo número de
  linhas antes e depois de N retrações; a varredura pelo histórico lê as linhas
  acumuladas até a base, e a leitura descartada pela guarda do contador também
  entra na conta. O contador só cresce, como a base (D18).

  ## Referências

  - Requisitos e aceite: `docs/_sprints/s01-nucleo-enoch/03_spec/handovers/spec.md`
    (R1, R4, R6, R8, R16, R25), com as varreduras e os índices do SQLite no Anexo A.
  - Decisões: `docs/adr/0002-modelo-acumulativo-log-estado-atual-historico.md` e
    `docs/adr/0003-memory-ets-contador-base-e-recuperacao.md`.
  - Vocabulário: `CONTEXT.md`; árvore: `docs/arquitetura.md`.
  - Suíte reutilizável por qualquer adaptador: `Enoch.Storage.ContractCase` (D24).
  """

  alias Enoch.DB

  @doc """
  A versão do layout que este pacote conhece (D34, R31).

  O passo 1 da subida compara com ela a versão que o storage aberto reporta
  (`c:layout_version/1`): um layout mais novo que este impede a subida. A versão
  é gravada pelo adaptador que a persiste; o `Memory`, volátil, não persiste
  layout e responde a versão conhecida.
  """
  @spec layout_version() :: non_neg_integer()
  @layout_version 0
  def layout_version, do: @layout_version

  @typedoc "Identificador de entidade."
  @type e :: integer()

  @typedoc "Identificador de atributo."
  @type a :: integer()

  @typedoc "Valor do datom."
  @type v :: term()

  @typedoc "Número de ordem da transação."
  @type tx :: pos_integer()

  @typedoc """
  Datom lido de uma varredura: `{e, a, v, tx, added}`.

  No estado atual, `tx` e `added` vêm `nil`; no histórico, trazem a transação que
  operou o datom e se ele foi afirmado (`true`) ou retraído (`false`).
  """
  @type datom :: {e(), a(), v(), tx() | nil, boolean() | nil}

  @typedoc "Datom a escrever: `{e, a, v, added}`. O `tx` é do adaptador."
  @type write :: {e(), a(), v(), boolean()}

  @typedoc "Referência opaca à instância do adaptador."
  @type t :: term()

  @typedoc "Opções de varredura: as chaves de pushdown de cada índice."
  @type scan_opts :: keyword()

  @doc """
  Abre a instância e cria as tabelas no processo que a chama.

  Quem chama fica dono das tabelas; o adaptador não presume dono (D18). As opções
  obrigatórias do adaptador são validadas aqui: o `Memory` não sobe sem
  `max_memory` (D20, R16).
  """
  @callback open(opts :: keyword()) :: {:ok, t()} | {:error, term()}

  @doc "O banco como valor na base publicada pela instância (D16, D18)."
  @callback db(t()) :: DB.t()

  @doc """
  Escreve uma transação no histórico e no estado atual, e devolve o `t` dela.

  Os datoms são crus, `{e, a, v, added}`: unicidade, cardinalidade, tipos e
  imutabilidade são do transactor (D14, s02). A ordem da escrita é a da D18.
  """
  @callback append(t(), [write()]) :: {:ok, tx()} | {:error, term()}

  @doc """
  Varredura EAVT: por entidade e, quando pedido, por atributo.

  Pushdown obrigatório: `e`. Opcional: `a`.
  """
  @callback scan_eavt(DB.t(), scan_opts()) :: [datom()]

  @doc """
  Varredura AEVT: por atributo e, quando pedido, por entidade.

  Pushdown obrigatório: `a`. Opcional: `e`.
  """
  @callback scan_aevt(DB.t(), scan_opts()) :: [datom()]

  @doc """
  Varredura AVET: por atributo e por valor exato ou por faixa de valores
  (atributos indexados, D16).

  Pushdown obrigatório: `a` e (`v`, ou `min_v` e `max_v` — a faixa inclui os
  limites).
  """
  @callback scan_avet(DB.t(), scan_opts()) :: [datom()]

  @doc """
  Varredura VAET: por valor referência e, quando pedido, por atributo.

  Pushdown obrigatório: `v` (o id da entidade referenciada). Opcional: `a`.
  """
  @callback scan_vaet(DB.t(), scan_opts()) :: [datom()]

  @doc """
  As linhas que as varreduras leram, acumuladas desde `c:open/1` (D17, critério
  3; R6).

  A diferença entre duas leituras diz quantas linhas uma varredura leu. A
  varredura pelo estado atual lê só os datoms vivos e o histórico não entra na
  conta; a varredura pelo histórico lê as linhas acumuladas até a base, e a
  leitura do estado atual que a guarda do contador invalidar também conta. O
  contador só cresce, como a base (D18). O evento de telemetria `rows_read` é da
  s05 (R17); o contrato expõe o número desde a s01.
  """
  @callback rows_read(t()) :: non_neg_integer()

  @doc """
  A versão do layout gravada no storage aberto (D34, R31).

  O passo 1 da subida a confere contra `layout_version/0` e recusa um layout mais
  novo que o conhecido, com erro explícito. É opcional: um adaptador que não
  persiste layout, como o `Memory`, não precisa implementá-la, e a subida usa a
  versão conhecida. No SQLite a versão sai do arquivo (`PRAGMA user_version`,
  s04).
  """
  @callback layout_version(t()) :: non_neg_integer()

  @optional_callbacks layout_version: 1
end
