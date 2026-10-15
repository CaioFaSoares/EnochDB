defmodule Enoch.Adapters.Memory do
  @moduledoc """
  Adaptador `Memory`: histórico e estado atual em ETS, com a base no contador.

  Duas tabelas ETS — o histórico, `ordered_set` e só com inserção, e o estado
  atual — mais um contador em `:atomics` que **é** a base (D18, R4):

  - o contador vale `2t` com a base estável em `t` e `2t+1` enquanto a transação
    `t+1` escreve; a base publicada no banco como valor é `div(contador, 2)`;
  - o escritor segue a ordem da D18: contador para `2t+1`, histórico, estado
    atual, contador para `2t+2`;
  - o contador nunca diminui.

  A varredura lê o estado atual quando o contador vale `2b` para a base `b` do
  banco como valor e, em qualquer outro caso, lê o histórico até `b` — a escolha
  de índice da D16, com o contador da D18. A guarda do contador vale **antes e
  depois** da varredura do estado atual: uma escrita que comece no meio dela
  invalida aquelas linhas, e aquela varredura é refeita pelo histórico na mesma
  base, uma vez, sem laço (D18) — a consulta não sofre starvation sob escrita
  contínua e as demais cláusulas seguem coerentes na mesma base. O escritor é
  único (D14).

  O `:atomics` da instância tem dois contadores: o slot 1 é a base e o slot 2
  acumula as linhas lidas pelas varreduras (D17, critério 3), expostas em
  `rows_read/1`.

  ## Limite conhecido da varredura

  São duas tabelas, e cada uma tem uma ordem só: a chave do histórico é
  `{e, a, v, tx}` e a do estado atual é `{e, a, v}`. A varredura EAVT usa o
  prefixo da chave; AEVT, AVET e VAET filtram por match spec dentro do ETS, sem
  trazer para quem chama as linhas descartadas. Os quatro índices covering são do
  SQLite (s04, Anexo A da spec).

  ## Retração

  Nada é alterado no lugar (D16): retrair insere uma linha com `added = false` no
  histórico e apaga o datom do estado atual, que é só a projeção dos vivos.

  ## Recuperação e sobrevivência das tabelas

  A escrita de uma transação não é atômica: são várias linhas no histórico e outras
  tantas no estado atual. Uma queda do transactor no meio da transação `t+1` deixa
  linhas órfãs com `tx = t+1` e o contador em `2t+1`; `recover/1` desfaz isso sem
  nunca voltar o contador (D18, ADR-0003): as órfãs saem do histórico, o estado
  atual é reconstruído do histórico até `t` e o contador é publicado em `2(t+1)`. A
  transação `t+1` fica vazia e a próxima real é `t+2`.

  As duas tabelas nascem no processo que chama `open/1` — o dono da instância, não
  o transactor (D18, D21) — e a opção `:heir` diz quem as herda se o dono morrer:
  com o dono fora do transactor, a queda do transactor não leva as tabelas.

  Referências: `docs/_sprints/s01-nucleo-enoch/03_spec/handovers/spec.md` (R2, R4,
  R5, R6, R8, R16), `docs/adr/0003-*.md` e `docs/arquitetura.md`. Suíte de contrato:
  `Enoch.Storage.ContractCase`; suíte do leitor: `test/enoch/storage/reader_test.exs`;
  suíte da recuperação: `test/enoch/adapters/memory_recovery_test.exs`.
  """

  @behaviour Enoch.Storage

  alias Enoch.DB

  # Os dois contadores da instância, no mesmo `:atomics`: o slot 1 é a base
  # (D18) e o slot 2 acumula as linhas lidas pelas varreduras (D17, critério 3).
  @base 1
  @rows_read 2

  @typedoc """
  Instância do adaptador: as referências das tabelas e do contador, e as opções
  de subida (entre elas o `max_memory`, para a cota da s05).
  """
  @type t :: %{refs: refs(), opts: keyword()}

  @typep refs :: {:ets.tid(), :ets.tid(), :atomics.atomics_ref()}

  @impl Enoch.Storage
  @spec open(keyword()) :: {:ok, t()} | {:error, term()}
  def open(opts) when is_list(opts) do
    with {:ok, _max_memory} <- max_memory(opts),
         {:ok, heir} <- heir(opts) do
      {:ok,
       %{
         refs: {
           new_table(:enoch_memory_history, heir),
           new_table(:enoch_memory_current, heir),
           :atomics.new(2, signed: false)
         },
         opts: opts
       }}
    end
  end

  # As duas tabelas nascem no processo que chama `open/1` — no caminho da
  # instância, o dono (`Enoch.Instance.Owner`), que passa o supervisor da instância
  # em `:heir`. Com o heir, as tabelas são herdadas por ele se o dono morrer; sem
  # ele, morrem junto (D18, D21, R5).
  defp new_table(name, nil), do: :ets.new(name, [:ordered_set, :public])

  defp new_table(name, heir) when is_pid(heir),
    do: :ets.new(name, [:ordered_set, :public, {:heir, heir, nil}])

  # O `:heir` é opcional e do dono; um valor que não é processo é erro de subida,
  # como o `max_memory` (D20).
  defp heir(opts) do
    case Keyword.fetch(opts, :heir) do
      :error -> {:ok, nil}
      {:ok, pid} when is_pid(pid) -> {:ok, pid}
      {:ok, other} -> {:error, {:invalid_option, {:heir, other}}}
    end
  end

  @impl Enoch.Storage
  @spec db(t()) :: DB.t()
  def db(%{refs: {_history, _current, counter} = refs}) do
    DB.new(refs, div(:atomics.get(counter, @base), 2))
  end

  @impl Enoch.Storage
  @spec rows_read(t()) :: non_neg_integer()
  def rows_read(%{refs: {_history, _current, counter}}), do: :atomics.get(counter, @rows_read)

  # O `Memory` é volátil e não persiste layout (D34): a versão que ele reporta é a
  # que este pacote conhece, e o passo 1 da subida nunca a recusa por mais nova. Um
  # adaptador que persiste layout — o SQLite da s04 — lê a versão do arquivo.
  @impl Enoch.Storage
  @spec layout_version(t()) :: non_neg_integer()
  def layout_version(%{}), do: Enoch.Storage.layout_version()

  @impl Enoch.Storage
  @spec append(t(), [Enoch.Storage.write()]) :: {:ok, Enoch.Storage.tx()} | {:error, term()}
  def append(%{refs: {history, current, counter}}, datoms) when is_list(datoms) do
    tx = begin_tx(counter)
    write_history(history, tx, datoms)
    apply_current(current, datoms)
    publish_tx(counter, tx)

    {:ok, tx}
  end

  @doc false
  # Primeira fase da ordem da D18: publica `2t + 1` e devolve o `t` da transação.
  # Pública para o teste da ordem; o caminho normal é `append/2`.
  @spec begin_tx(:atomics.atomics_ref()) :: Enoch.Storage.tx()
  def begin_tx(counter) do
    tx = div(:atomics.get(counter, @base), 2) + 1
    :atomics.put(counter, @base, 2 * tx - 1)
    tx
  end

  @doc false
  # Segunda fase: o histórico recebe a linha de cada datom, com o `tx` da transação.
  @spec write_history(:ets.tid(), Enoch.Storage.tx(), [Enoch.Storage.write()]) :: :ok
  def write_history(history, tx, datoms) do
    Enum.each(datoms, fn {e, a, v, added} -> :ets.insert(history, {{e, a, v, tx}, added}) end)
  end

  @doc false
  # Terceira fase: o estado atual recebe a projeção dos datoms vivos. O objeto é o
  # datom embrulhado numa tupla de um elemento, para a chave do ETS ser `{e, a, v}`
  # e não só `e`.
  @spec apply_current(:ets.tid(), [Enoch.Storage.write()]) :: :ok
  def apply_current(current, datoms) do
    Enum.each(datoms, fn
      {e, a, v, true} -> :ets.insert(current, {{e, a, v}})
      {e, a, v, false} -> :ets.delete(current, {e, a, v})
    end)
  end

  @doc false
  # Quarta fase: publica a base estável em `t + 1`.
  @spec publish_tx(:atomics.atomics_ref(), Enoch.Storage.tx()) :: :ok
  def publish_tx(counter, tx), do: :atomics.put(counter, @base, 2 * tx)

  @doc """
  Recupera a instância de uma queda do transactor no meio da escrita (R5, D18).

  O contador é a testemunha: vale `2t` com a base estável em `t` e `2t+1` enquanto
  a transação `t+1` escreve, e nunca diminui (D18). Com ele em `2t+1`, a `t+1` morreu
  no meio, e a ordem da ADR-0003 é esta: o contador fica onde está — os leitores vão
  ao histórico, onde as órfãs `tx = t+1` são invisíveis para `b <= t`; as linhas
  órfãs de `t+1` saem do histórico; o estado atual é reconstruído do histórico até
  `t`; e o contador é publicado em `2(t+1)`. A `t+1` vira uma transação vazia e a
  próxima real é `t+2`, porque um `t` nunca é reutilizado.

  Com o contador em `2t` não há transação em curso e nada é feito: a chamada é
  barata, e é o `Enoch.Instance.Owner` que a faz quando entrega o storage ao
  transactor, para o escritor novo só começar a escrever sobre estado limpo.

  A limpeza é a única que apaga linha do histórico: a `t+1` não chegou a existir
  para quem lê (ADR-0002).

  `recover/1` é só a queda no meio da escrita. A conferência do passo 2 da subida
  (D34, R31) — o estado atual contra o log, com o contador par — é `verify/1`.
  """
  @spec recover(t()) :: :ok
  def recover(%{refs: {history, _current, counter}} = storage) do
    case :atomics.get(counter, @base) do
      writing when rem(writing, 2) == 1 ->
        # `div(2t+1, 2) = t`: a transação que caiu é a `t+1`.
        tx = div(writing, 2) + 1
        delete_orphans(history, tx)
        rebuild_current(storage, tx - 1)
        publish_tx(counter, tx)
        :ok

      _published ->
        :ok
    end
  end

  @doc """
  Confere o estado atual contra o log e reconstrói o atual se divergirem (R31, D34).

  É a **conferência do passo 2 da subida**: o storage confere que o estado atual e
  o log concordam e reconstrói o atual se divergirem. É a função que
  `Enoch.Instance.Boot` chama no passo 2 (por `function_exported?/3`, como o dono
  faz com `recover/1`).

  Com o contador ímpar a transação morreu no meio da escrita e a conferência é a
  recuperação de `recover/1`. Com o contador par, a transação não está em curso: o
  estado atual é comparado com a projeção dos vivos do histórico até a base e, se
  divergir — uma linha adulterada, um datom apagado —, é reconstruído por
  `rebuild_current/2`.

  A comparação custa O(histórico), o preço que a ADR-0003 já aceita no reinício:
  a varredura do histórico acontece de qualquer forma, para conferir. Sem
  divergência, o estado atual é deixado como está.
  """
  @spec verify(t()) :: :ok
  def verify(%{refs: {history, current, counter}} = storage) do
    case :atomics.get(counter, @base) do
      writing when rem(writing, 2) == 1 ->
        recover(storage)

      published ->
        basis_t = div(published, 2)

        if valid_current?(history, current, basis_t) do
          :ok
        else
          rebuild_current(storage, basis_t)
        end
    end
  end

  defp valid_current?(history, current, basis_t) do
    live = live_datoms(history, basis_t) |> MapSet.new()

    present =
      :ets.foldl(fn {{e, a, v}}, acc -> MapSet.put(acc, {e, a, v}) end, MapSet.new(), current)

    present == live
  end

  # As linhas órfãs da transação que caiu. O `tx` é literal no padrão, e o ETS
  # percorre a tabela uma vez para apagá-las.
  defp delete_orphans(history, tx) do
    :ets.select_delete(history, [{{{:"$1", :"$2", :"$3", tx}, :_}, [], [true]}])
  end

  @doc """
  Reconstrói o estado atual a partir do histórico até `basis_t` (R5, D18).

  Apaga o estado atual e o refaz com o último operador por `(e, a, v)` com
  `tx <= basis_t` — a mesma visibilidade do histórico que o avaliador aplica (D8):
  as linhas do mesmo `(e, a, v)` são reduzidas à de maior `tx`, e só as afirmadas
  ficam vivas. Custa O(histórico), o preço que a ADR-0003 aceita na recuperação.

  É a reconstrução que `recover/1` usa; o passo 2 da subida (D34, R31) reconstrói
  com ela quando o estado atual diverge do histórico.
  """
  @spec rebuild_current(t(), DB.basis_t()) :: :ok
  def rebuild_current(%{refs: {history, current, _counter}}, basis_t) do
    live = live_datoms(history, basis_t)

    :ets.delete_all_objects(current)
    Enum.each(live, fn {e, a, v} -> :ets.insert(current, {{e, a, v}}) end)

    :ok
  end

  # O último operador por `(e, a, v)` com `tx <= basis_t`, num mapa: vale o de maior
  # `tx`, e a travessia do histórico não precisa de ordem. As órfãs que sobraram
  # ficam de fora pela comparação do `tx`.
  defp live_datoms(history, basis_t) do
    last =
      :ets.foldl(
        fn
          {{_e, _a, _v, tx}, _added}, acc when tx > basis_t ->
            acc

          {{e, a, v, tx}, added}, acc ->
            datom = {e, a, v}

            case acc do
              %{^datom => {seen_tx, _seen_added}} when seen_tx >= tx -> acc
              _ -> Map.put(acc, datom, {tx, added})
            end
        end,
        %{},
        history
      )

    for {datom, {_tx, true}} <- last, do: datom
  end

  @impl Enoch.Storage
  @spec scan_eavt(DB.t(), Enoch.Storage.scan_opts()) :: [Enoch.Storage.datom()]
  def scan_eavt(db, opts) do
    e = required!(opts, :e, :scan_eavt)

    case Keyword.fetch(opts, :a) do
      {:ok, a} -> scan(db, {:eavt, e, a})
      :error -> scan(db, {:eavt, e})
    end
  end

  @impl Enoch.Storage
  @spec scan_aevt(DB.t(), Enoch.Storage.scan_opts()) :: [Enoch.Storage.datom()]
  def scan_aevt(db, opts) do
    a = required!(opts, :a, :scan_aevt)

    case Keyword.fetch(opts, :e) do
      {:ok, e} -> scan(db, {:aevt, a, e})
      :error -> scan(db, {:aevt, a})
    end
  end

  @impl Enoch.Storage
  @spec scan_avet(DB.t(), Enoch.Storage.scan_opts()) :: [Enoch.Storage.datom()]
  def scan_avet(db, opts) do
    a = required!(opts, :a, :scan_avet)

    cond do
      Keyword.has_key?(opts, :v) ->
        scan(db, {:avet, a, Keyword.fetch!(opts, :v)})

      Keyword.has_key?(opts, :min_v) and Keyword.has_key?(opts, :max_v) ->
        scan(db, {:avet_range, a, Keyword.fetch!(opts, :min_v), Keyword.fetch!(opts, :max_v)})

      true ->
        raise ArgumentError,
              "scan_avet/2 exige a opção :v ou as opções :min_v e :max_v; recebeu #{inspect(opts)}"
    end
  end

  @impl Enoch.Storage
  @spec scan_vaet(DB.t(), Enoch.Storage.scan_opts()) :: [Enoch.Storage.datom()]
  def scan_vaet(db, opts) do
    v = required!(opts, :v, :scan_vaet)

    case Keyword.fetch(opts, :a) do
      {:ok, a} -> scan(db, {:vaet, v, a})
      :error -> scan(db, {:vaet, v})
    end
  end

  # A base escolhe a varredura (item 23 da D18): com o contador em `2b` a base `b`
  # é a estável e vale o estado atual; em qualquer outro caso vale o histórico. A
  # guarda vale antes **e** depois da varredura do estado atual: uma escrita que
  # comece no meio dela invalida aquelas linhas, e a varredura é refeita pelo
  # histórico na mesma base — uma vez, sem laço, para a consulta não sofrer
  # starvation sob escrita contínua (D18).
  defp scan(db, filter) do
    {history, current, counter} = DB.refs(db)
    basis_t = DB.basis_t(db)

    if stable?(counter, basis_t) do
      rows = count_rows(present_scan(current, filter), counter)

      if stable?(counter, basis_t) do
        rows
      else
        fallback_rows(history, filter, basis_t, counter)
      end
    else
      fallback_rows(history, filter, basis_t, counter)
    end
  end

  # O contador **é** a base (D18): ele vale `2t` com a base estável em `t` e
  # `2t + 1` enquanto a transação `t + 1` escreve. A base `b` do banco como valor
  # está estável exatamente quando o contador vale `2b`.
  defp stable?(counter, basis_t), do: :atomics.get(counter, @base) == 2 * basis_t

  # A varredura refeita pelo histórico, na mesma base do banco como valor: a
  # primeira validação que falhar manda para cá, e daqui não se volta ao estado
  # atual (D18).
  defp fallback_rows(history, filter, basis_t, counter) do
    history_scan(history, filter, basis_t) |> count_rows(counter)
  end

  # As linhas que a varredura leu entram no contador da instância (D17, critério
  # 3): o total só cresce, e a diferença entre duas leituras é o custo de uma
  # varredura. A leitura do estado atual descartada pela guarda também conta.
  defp count_rows(rows, counter) do
    :atomics.add(counter, @rows_read, length(rows))
    rows
  end

  # Estado atual: a chave é o datom, `{e, a, v}`, e o datom sai sem `tx` e sem
  # `added` (Anexo A: `datoms(e, a, v)`). O objeto da tabela embrulha o datom numa
  # tupla de um elemento, e o corpo do match spec faz o mesmo: é assim que o ETS
  # constrói uma tupla literal.
  defp present_scan(table, filter) do
    {key, guards} = index_spec(filter)
    :ets.select(table, [{{key}, guards, [{present_datom(key)}]}])
  end

  defp present_datom({e, a, v}), do: {e, a, v, nil, nil}

  # Histórico: a chave é `{e, a, v, tx}` e o `added` é o objeto; o pushdown por
  # `t` entra aqui, e só as linhas com `tx <= basis_t` saem. As linhas do mesmo
  # `(e, a, v)` saem adjacentes e ordenadas por `tx`, porque a chave ordena por
  # `{e, a, v, tx}`.
  defp history_scan(table, filter, basis_t) do
    {key, guards} = index_spec(filter)
    {e, a, v} = key
    pattern = {{e, a, v, :"$90"}, :"$91"}
    body = {{e, a, v, :"$90", :"$91"}}

    :ets.select(table, [{pattern, [{:"=<", :"$90", basis_t} | guards], [body]}])
  end

  # O filtro de cada varredura vira o padrão da chave e as guardas do match spec.
  # Onde não há pushdown, a posição é uma variável.
  defp index_spec({:eavt, e}), do: {{e, :"$1", :"$2"}, []}
  defp index_spec({:eavt, e, a}), do: {{e, a, :"$1"}, []}
  defp index_spec({:aevt, a}), do: {{:"$1", a, :"$2"}, []}
  defp index_spec({:aevt, a, e}), do: {{e, a, :"$1"}, []}
  defp index_spec({:avet, a, v}), do: {{:"$1", a, v}, []}

  defp index_spec({:avet_range, a, min_v, max_v}),
    do: {{:"$1", a, :"$2"}, [{:>=, :"$2", min_v}, {:"=<", :"$2", max_v}]}

  defp index_spec({:vaet, v}), do: {{:"$1", :"$2", v}, []}
  defp index_spec({:vaet, v, a}), do: {{:"$1", a, v}, []}

  defp required!(opts, key, callback) do
    case Keyword.fetch(opts, key) do
      {:ok, value} ->
        value

      :error ->
        raise ArgumentError,
              "#{callback}/2 exige a opção #{inspect(key)}; recebeu #{inspect(opts)}"
    end
  end

  # D20: o `max_memory` é obrigatório; `:infinity` é permitido e explícito. A cota
  # e o alerta do limite brando são da s05; aqui só a obrigatoriedade.
  defp max_memory(opts) do
    case Keyword.fetch(opts, :max_memory) do
      {:ok, :infinity} -> {:ok, :infinity}
      {:ok, bytes} when is_integer(bytes) and bytes > 0 -> {:ok, bytes}
      {:ok, other} -> {:error, {:invalid_option, {:max_memory, other}}}
      :error -> {:error, {:missing_option, :max_memory}}
    end
  end
end
