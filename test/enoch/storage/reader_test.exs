defmodule Enoch.Storage.Reader.MemoryTest do
  @moduledoc """
  O leitor do `Memory`: a guarda do contador antes e depois da varredura, o
  refazimento pelo histórico na mesma base e o contador de linhas lidas (R4, R6,
  D17 critério 3, D18).

  A suíte fica fora da `Enoch.Storage.ContractCase` de propósito: a de contrato
  exclui a leitura concorrente e o contador de linhas, e diz no próprio moduledoc
  que são de outra suíte. O `Memory` é o único adaptador da s01; a s04 acrescenta
  o SQLite.

  Cada validação da guarda tem a sua corrida: a de antes, com o contador preso no
  meio de uma transação; a de depois, com a escrita caindo entre as duas
  validações. O caminho fica visível pelo contador de linhas lidas — a varredura
  do estado atual lê só os datoms vivos, e a do histórico lê as linhas acumuladas
  até a base, então uma leitura refeita paga as duas.

  Referências: `docs/_sprints/s01-nucleo-enoch/03_spec/handovers/spec.md` (R4, R6)
  e `docs/adr/0003-*.md`.
  """

  use ExUnit.Case, async: true

  alias Enoch.Adapters.Memory
  alias Enoch.DB

  @adapter Memory
  @aberto [max_memory: :infinity]

  describe "contador de linhas lidas (R6, D17 critério 3)" do
    test "o adaptador expõe as linhas lidas por varredura" do
      callbacks = Enoch.Storage.behaviour_info(:callbacks)
      assert :rows_read in Enum.map(callbacks, &elem(&1, 0)), "o contrato não declara rows_read/1"

      {:ok, storage} = @adapter.open(@aberto)
      assert 0 == @adapter.rows_read(storage)

      assert {:ok, 1} =
               @adapter.append(storage, [
                 {100, 10, 1, true},
                 {101, 10, 2, true},
                 {102, 20, 3, true}
               ])

      # Gravar não lê: o contador é da varredura.
      assert 0 == @adapter.rows_read(storage)

      db = @adapter.db(storage)

      %{rows: rows, read: read} = scan_read(storage, fn -> @adapter.scan_aevt(db, a: 10) end)
      assert rows == [{100, 10, 1, nil, nil}, {101, 10, 2, nil, nil}]
      assert 2 == read

      %{rows: rows, read: read} = scan_read(storage, fn -> @adapter.scan_aevt(db, a: 20) end)
      assert rows == [{102, 20, 3, nil, nil}]
      assert 1 == read

      # A varredura que não casa nada lê zero linha.
      %{rows: rows, read: read} = scan_read(storage, fn -> @adapter.scan_aevt(db, a: 30) end)
      assert rows == []
      assert 0 == read
    end

    test "uma consulta ao presente lê o mesmo número de linhas antes e depois de N retrações" do
      {:ok, storage} = @adapter.open(@aberto)

      assert {:ok, 1} = @adapter.append(storage, for(e <- 1..50, do: {e, 10, e, true}))

      %{rows: antes, read: lidas_antes} =
        scan_read(storage, fn -> @adapter.scan_aevt(@adapter.db(storage), a: 10) end)

      assert 50 == length(antes)
      assert 50 == lidas_antes

      # N retrações do atributo, cada uma seguida da reafirmação do mesmo datom: o
      # conjunto vivo do presente não muda de tamanho e o histórico cresce.
      retracoes = 25

      for e <- 1..retracoes do
        assert {:ok, _tx} = @adapter.append(storage, [{e, 10, e, false}])
        assert {:ok, _tx} = @adapter.append(storage, [{e, 10, e, true}])
      end

      db = @adapter.db(storage)

      %{rows: depois, read: lidas_depois} =
        scan_read(storage, fn -> @adapter.scan_aevt(db, a: 10) end)

      assert 50 == length(depois)
      assert 50 == lidas_depois

      # O histórico acumulou as 2N linhas: a mesma varredura numa base passada lê
      # as 50 linhas da primeira transação mais as 2N - 1 linhas até essa base. O
      # presente não pagou por elas.
      base_passada = DB.new(DB.refs(db), DB.basis_t(db) - 1)

      %{read: lidas_passado} =
        scan_read(storage, fn -> @adapter.scan_aevt(base_passada, a: 10) end)

      assert 50 + (2 * retracoes - 1) == lidas_passado
    end
  end

  describe "a guarda do contador (R4, D18)" do
    test "com a escrita em curso, a varredura é refeita pelo histórico na mesma base, uma vez" do
      assert {:ok, %{refs: {history, current, counter}} = storage} = @adapter.open(@aberto)

      assert {:ok, 1} = @adapter.append(storage, [{100, 10, 1, true}, {101, 10, 2, true}])

      db = @adapter.db(storage)
      assert 1 == DB.basis_t(db)
      assert 2 == :atomics.get(counter, 1)

      # O escritor começa a transação 2 e para no meio dela, como o teste da ordem
      # faz com as fases da D18: o contador fica em `2b + 1`, e o histórico e o
      # estado atual já têm as linhas novas — o presente fica com três datoms
      # vivos, e o histórico até a base 1, com dois.
      assert 2 == Memory.begin_tx(counter)

      em_curso = [{100, 10, 1, false}, {100, 10, 99, true}, {101, 10, 99, true}]
      assert :ok == Memory.write_history(history, 2, em_curso)
      assert :ok == Memory.apply_current(current, em_curso)
      assert 3 == :atomics.get(counter, 1)

      varredura = scan_read(storage, fn -> @adapter.scan_aevt(db, a: 10) end)

      # A base do banco como valor é 1 e o contador não vale `2b`: a varredura sai
      # pelo histórico, na mesma base, e só uma vez — o estado atual não foi lido,
      # e a varredura não repetiu em laço.
      assert varredura.rows == [{100, 10, 1, 1, true}, {101, 10, 2, 1, true}]
      assert 2 == varredura.read

      # Publicada a transação, a base 2 vê o datom novo pelo estado atual.
      assert :ok == Memory.publish_tx(counter, 2)

      db2 = @adapter.db(storage)
      assert 2 == DB.basis_t(db2)
      assert @adapter.scan_aevt(db2, e: 100, a: 10) == [{100, 10, 99, nil, nil}]
    end

    test "a escrita entre as duas validações refaz a varredura pelo histórico na mesma base" do
      assert {:ok, storage} = @adapter.open(@aberto)

      # O presente é grande de propósito: a varredura do estado atual percorre a
      # tabela inteira, e a janela dela cobre a escrita.
      entidades = 5_000
      assert {:ok, 1} = @adapter.append(storage, for(e <- 1..entidades, do: {e, 10, e, true}))

      pai = self()
      escritor = spawn(fn -> write_on_signal(storage, pai) end)
      monitor = Process.monitor(escritor)

      # A escrita tem de cair entre as duas validações do contador: o leitor
      # sinaliza o escritor e varre em seguida. Quando a escrita chega antes da
      # primeira validação, a leitura sai pelo histórico e não paga a varredura do
      # estado atual — é outra assinatura, e o teste tenta de novo.
      observada =
        Enum.find_value(1..50, fn _tentativa ->
          db = @adapter.db(storage)
          base = DB.basis_t(db)
          antes = @adapter.rows_read(storage)

          leitura =
            Task.async(fn ->
              send(escritor, :escreva)
              @adapter.scan_aevt(db, a: 10)
            end)

          assert_receive {:escrito, _tx}, 5_000
          rows = Task.await(leitura, 5_000)
          read = @adapter.rows_read(storage) - antes

          # A leitura refeita paga a varredura do estado atual, descartada pela
          # guarda, mais a do histórico: é a assinatura da validação de depois.
          if read > length(rows), do: {base, rows, read}
        end)

      send(escritor, :pare)
      assert_receive {:DOWN, ^monitor, :process, ^escritor, :normal}, 5_000

      assert observada, "a escrita não caiu entre as duas validações em 50 tentativas"
      {base, rows, read} = observada

      assert Enum.all?(rows, fn {_e, _a, _v, tx, _added} -> is_nil(tx) or tx <= base end)
      assert live(rows) == expected(base, entidades)
      assert read > length(rows)
    end

    test "leitura concorrente com escrita contínua termina e é consistente com a base" do
      {:ok, storage} = @adapter.open(@aberto)

      entidades = 500
      assert {:ok, 1} = @adapter.append(storage, for(e <- 1..entidades, do: {e, 10, e, true}))

      escritor = spawn(fn -> write_forever(storage, 1, 3_000) end)
      monitor = Process.monitor(escritor)

      leituras = read_concurrently(storage, 300)

      send(escritor, :pare)
      assert_receive {:DOWN, ^monitor, :process, ^escritor, :normal}, 5_000

      bases = leituras |> Enum.map(fn {base, _rows, _read} -> base end) |> Enum.uniq()
      assert length(bases) > 1, "o escritor não avançou durante a leitura"

      for {base, rows, _read} <- leituras do
        assert Enum.all?(rows, fn {_e, _a, _v, tx, _added} -> is_nil(tx) or tx <= base end),
               "linha acima da base #{base} numa varredura"

        assert live(rows) == expected(base, entidades),
               "a leitura da base #{base} divergiu do estado da base"
      end

      historico = Enum.filter(leituras, fn {_b, rows, _r} -> historico?(rows) end)
      assert historico != [], "a guarda do contador não disparou sob escrita contínua"
    end
  end

  # --- auxiliares da suíte -----------------------------------------------------

  # As linhas que a varredura leu, pelo contador da instância (D17, critério 3).
  defp scan_read(storage, scan) do
    antes = @adapter.rows_read(storage)
    rows = scan.()
    %{rows: rows, read: @adapter.rows_read(storage) - antes}
  end

  # As leituras concorrentes com o escritor: cada uma captura o banco como valor e
  # varre o atributo do caso, guardando a base, as linhas e o que a varredura leu.
  defp read_concurrently(storage, times) do
    await_base(storage)

    for _ <- 1..times do
      db = @adapter.db(storage)
      base = DB.basis_t(db)
      %{rows: rows, read: read} = scan_read(storage, fn -> @adapter.scan_aevt(db, a: 10) end)
      {base, rows, read}
    end
  end

  # As linhas da varredura do histórico trazem o `tx`; as do estado atual, não.
  defp historico?(rows), do: Enum.any?(rows, fn {_e, _a, _v, tx, _added} -> not is_nil(tx) end)

  # O estado vivo na base, a partir das linhas que a varredura devolveu: no
  # presente as linhas já são os datoms vivos; no histórico vale o último operador
  # por `(e, a, v)` com `tx <= base`. O avaliador resolve a visibilidade no
  # produto (D8); aqui é só o oráculo do teste.
  defp live(rows) do
    if Enum.all?(rows, fn {_e, _a, _v, tx, _added} -> is_nil(tx) end) do
      rows
      |> Enum.map(fn {e, a, v, _tx, _added} -> {e, a, v} end)
      |> Enum.sort()
    else
      rows
      |> Enum.reduce(%{}, fn {e, a, v, tx, added}, vivo ->
        case Map.fetch(vivo, {e, a, v}) do
          {:ok, {tx_antigo, _added}} when tx_antigo >= tx -> vivo
          _ -> Map.put(vivo, {e, a, v}, {tx, added})
        end
      end)
      |> Enum.filter(fn {_datom, {_tx, added}} -> added end)
      |> Enum.map(fn {datom, _ultimo} -> datom end)
      |> Enum.sort()
    end
  end

  # O escritor da suíte só mexe na entidade 1 e afirma o `t` da transação como
  # valor: na base `b` o estado vivo da entidade 1 é o valor `b`, e as demais
  # entidades seguem como a primeira transação as afirmou.
  defp expected(base, entidades) do
    Enum.sort([{1, 10, max(base, 1)} | for(e <- 2..entidades, do: {e, 10, e})])
  end

  # Espera a primeira transação do escritor: uma leitura de base 0 não prova nada
  # da concorrência.
  defp await_base(storage, restantes \\ 1_000) do
    cond do
      DB.basis_t(@adapter.db(storage)) > 0 ->
        :ok

      restantes == 0 ->
        flunk("o escritor não publicou nenhuma transação")

      true ->
        Process.sleep(1)
        await_base(storage, restantes - 1)
    end
  end

  # Um escritor só (D14), que escreve sem parar até o `:pare` ou até terminar as
  # transações pedidas. Cada transação retrai o valor anterior da entidade 1 e
  # afirma o novo, que é o `t` dela; o `sleep(0)` cede a vez sem parar de escrever.
  defp write_forever(_storage, _tx, 0), do: :ok

  defp write_forever(storage, tx, restantes) do
    receive do
      :pare ->
        :ok
    after
      0 ->
        novo = tx + 1
        assert {:ok, ^novo} = @adapter.append(storage, [{1, 10, tx, false}, {1, 10, novo, true}])
        Process.sleep(0)
        write_forever(storage, novo, restantes - 1)
    end
  end

  # O escritor da corrida: escreve uma transação a cada sinal, pelas fases da D18
  # (como o teste da ordem), retraindo o valor anterior da entidade 1 e afirmando
  # o `t` da transação como valor novo.
  defp write_on_signal(%{refs: {history, current, counter}}, parent) do
    receive do
      :escreva ->
        tx = Memory.begin_tx(counter)
        escrita = [{1, 10, tx - 1, false}, {1, 10, tx, true}]
        :ok = Memory.write_history(history, tx, escrita)
        :ok = Memory.apply_current(current, escrita)
        :ok = Memory.publish_tx(counter, tx)
        send(parent, {:escrito, tx})
        write_on_signal(%{refs: {history, current, counter}}, parent)

      :pare ->
        :ok
    end
  end
end
