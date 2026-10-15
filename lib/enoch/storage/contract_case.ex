defmodule Enoch.Storage.ContractCase do
  @moduledoc """
  Suíte de contrato do `Enoch.Storage`, para rodar em qualquer adaptador (D24, R25).

      defmodule Enoch.Storage.Contract.MemoryTest do
        use Enoch.Storage.ContractCase,
          adapter: Enoch.Adapters.Memory,
          storage_opts: [max_memory: :infinity]
      end

  O adaptador precisa implementar o behaviour `Enoch.Storage`. As `storage_opts`
  vão para `adapter.open/1`, e é onde entram as opções obrigatórias do adaptador —
  o `max_memory` do `Memory` (D20). A suíte já traz o `use ExUnit.Case`; o módulo
  que a usa não o repete.

  A suíte cobre o contrato pelo caminho de fora: as quatro varreduras no presente
  e no passado, com o pushdown de cada índice, o modelo acumulativo (afirmar,
  retrair e reafirmar), o banco como valor de base antiga (o teste obrigatório da
  D18) e a ausência de consulta Datalog no contrato. Ela não cobre leitura
  concorrente nem recuperação: são da suíte de outra fatia.

  O estado atual reconstruído do histórico é conferido por um modelo de referência
  do próprio teste — vale o último operador por `(e, a, v)` com `tx <= b` —, lido
  pelas varreduras do histórico. A visibilidade do passado, no produto, é do
  avaliador (D8).

  Referências: `docs/_sprints/s01-nucleo-enoch/03_spec/handovers/spec.md` (R1, R2,
  R4, R8, R25) e `docs/adr/0003-*.md`.
  """

  use ExUnit.CaseTemplate

  using opts do
    adapter = Keyword.fetch!(opts, :adapter)
    storage_opts = Keyword.get(opts, :storage_opts, [])

    quote do
      use ExUnit.Case, async: false

      @adapter unquote(adapter)
      @storage_opts unquote(storage_opts)

      setup do
        {:ok, storage} = @adapter.open(@storage_opts)
        %{storage: storage}
      end

      test "o contrato não recebe consulta Datalog e não tem compile/2" do
        callbacks = Enoch.Storage.behaviour_info(:callbacks)
        names = Enum.map(callbacks, &elem(&1, 0))

        refute :compile in names
        refute function_exported?(Enoch.Storage, :compile, 2)
        refute :q in names
        refute :query in names

        for callback <- [:open, :db, :append, :scan_eavt, :scan_aevt, :scan_avet, :scan_vaet] do
          assert callback in names, "o contrato não declara #{callback}"
        end

        for callback <- [:scan_eavt, :scan_aevt, :scan_avet, :scan_vaet] do
          assert function_exported?(@adapter, callback, 2),
                 "#{inspect(@adapter)} não implementa #{callback}/2"
        end
      end

      test "cada varredura exige o filtro do seu índice", %{storage: storage} do
        db = @adapter.db(storage)

        assert_raise ArgumentError, ~r/exige a opção :e/, fn -> @adapter.scan_eavt(db, a: 10) end
        assert_raise ArgumentError, ~r/exige a opção :a/, fn -> @adapter.scan_aevt(db, e: 100) end

        assert_raise ArgumentError, ~r/exige a opção :a/, fn ->
          @adapter.scan_avet(db, v: 1)
        end

        assert_raise ArgumentError, ~r/:min_v/, fn -> @adapter.scan_avet(db, a: 10, min_v: 1) end
        assert_raise ArgumentError, ~r/exige a opção :v/, fn -> @adapter.scan_vaet(db, a: 10) end
      end

      test "afirmar, retrair e reafirmar o mesmo (e, a, v): três linhas no histórico, um datom atual",
           %{storage: storage} do
        assert {:ok, 1} = @adapter.append(storage, [{100, 10, 7, true}])
        assert {:ok, 2} = @adapter.append(storage, [{100, 10, 7, false}])
        assert {:ok, 3} = @adapter.append(storage, [{100, 10, 7, true}])

        escrito = present(@adapter.db(storage), [10])
        assert escrito == [{100, 10, 7}]

        db3 = @adapter.db(storage)
        assert {:ok, 4} = @adapter.append(storage, [{200, 10, 8, true}])

        do_historico = history(@adapter, db3, [10])

        assert sorted(do_historico) ==
                 sorted([
                   {100, 10, 7, 1, true},
                   {100, 10, 7, 2, false},
                   {100, 10, 7, 3, true}
                 ])

        assert reconstruct(do_historico) == escrito
      end

      test "as linhas do mesmo (e, a, v) chegam adjacentes e ordenadas por tx", %{
        storage: storage
      } do
        assert {:ok, 1} = @adapter.append(storage, [{100, 10, 7, true}, {101, 10, 7, true}])
        assert {:ok, 2} = @adapter.append(storage, [{100, 10, 7, false}])
        assert {:ok, 3} = @adapter.append(storage, [{100, 10, 7, true}])

        db3 = @adapter.db(storage)
        assert {:ok, 4} = @adapter.append(storage, [{300, 10, 9, true}])

        rows = @adapter.scan_aevt(db3, a: 10)

        assert Enum.filter(rows, &match?({100, _a, 7, _tx, _added}, &1)) == [
                 {100, 10, 7, 1, true},
                 {100, 10, 7, 2, false},
                 {100, 10, 7, 3, true}
               ]

        first = Enum.find_index(rows, &match?({100, 10, 7, 1, true}, &1))

        assert Enum.slice(rows, first, 3) == [
                 {100, 10, 7, 1, true},
                 {100, 10, 7, 2, false},
                 {100, 10, 7, 3, true}
               ]
      end

      test "EAVT: por entidade, com pushdown por a, no presente e no passado", %{storage: storage} do
        assert {:ok, 1} =
                 @adapter.append(storage, [
                   {100, 10, 1, true},
                   {100, 20, 101, true},
                   {101, 10, 2, true}
                 ])

        db1 = @adapter.db(storage)

        assert {:ok, 2} =
                 @adapter.append(storage, [{100, 10, 1, false}, {101, 20, 100, true}])

        assert sorted(@adapter.scan_eavt(db1, e: 100)) ==
                 sorted([{100, 10, 1, 1, true}, {100, 20, 101, 1, true}])

        assert @adapter.scan_eavt(db1, e: 100, a: 10) == [{100, 10, 1, 1, true}]
        assert @adapter.scan_eavt(db1, e: 100, a: 30) == []

        assert sorted(@adapter.scan_eavt(@adapter.db(storage), e: 100)) ==
                 sorted([{100, 20, 101, nil, nil}])

        assert @adapter.scan_eavt(@adapter.db(storage), e: 100, a: 10) == []
      end

      test "AEVT: por atributo, com pushdown por e, no presente e no passado", %{storage: storage} do
        assert {:ok, 1} =
                 @adapter.append(storage, [
                   {100, 10, 1, true},
                   {101, 10, 2, true},
                   {100, 20, 3, true}
                 ])

        db1 = @adapter.db(storage)
        assert {:ok, 2} = @adapter.append(storage, [{100, 10, 1, false}])

        assert sorted(@adapter.scan_aevt(db1, a: 10)) ==
                 sorted([{100, 10, 1, 1, true}, {101, 10, 2, 1, true}])

        assert @adapter.scan_aevt(db1, a: 10, e: 101) == [{101, 10, 2, 1, true}]
        assert @adapter.scan_aevt(db1, a: 30) == []

        assert @adapter.scan_aevt(@adapter.db(storage), a: 10) == [{101, 10, 2, nil, nil}]
        assert @adapter.scan_aevt(@adapter.db(storage), a: 20) == [{100, 20, 3, nil, nil}]
      end

      test "AVET: por atributo e valor ou faixa, no presente e no passado", %{storage: storage} do
        assert {:ok, 1} =
                 @adapter.append(storage, [
                   {100, 10, 5, true},
                   {101, 10, 7, true},
                   {102, 10, 9, true},
                   {103, 20, 7, true}
                 ])

        db1 = @adapter.db(storage)
        assert {:ok, 2} = @adapter.append(storage, [{100, 10, 5, false}])

        assert @adapter.scan_avet(db1, a: 10, v: 7) == [{101, 10, 7, 1, true}]
        assert @adapter.scan_avet(db1, a: 10, v: 20) == []

        assert sorted(@adapter.scan_avet(db1, a: 10, min_v: 6, max_v: 9)) ==
                 sorted([{101, 10, 7, 1, true}, {102, 10, 9, 1, true}])

        assert @adapter.scan_avet(@adapter.db(storage), a: 10, v: 5) == []

        assert sorted(@adapter.scan_avet(@adapter.db(storage), a: 10, min_v: 0, max_v: 100)) ==
                 sorted([{101, 10, 7, nil, nil}, {102, 10, 9, nil, nil}])
      end

      test "VAET: por valor referência, com pushdown por a, no presente e no passado",
           %{storage: storage} do
        assert {:ok, 1} =
                 @adapter.append(storage, [
                   {100, 20, 101, true},
                   {102, 20, 101, true},
                   {103, 20, 104, true},
                   {100, 30, 101, true}
                 ])

        db1 = @adapter.db(storage)
        assert {:ok, 2} = @adapter.append(storage, [{100, 20, 101, false}])

        assert sorted(@adapter.scan_vaet(db1, v: 101)) ==
                 sorted([
                   {100, 20, 101, 1, true},
                   {102, 20, 101, 1, true},
                   {100, 30, 101, 1, true}
                 ])

        assert sorted(@adapter.scan_vaet(db1, v: 101, a: 20)) ==
                 sorted([{100, 20, 101, 1, true}, {102, 20, 101, 1, true}])

        assert @adapter.scan_vaet(db1, v: 104) == [{103, 20, 104, 1, true}]
        assert @adapter.scan_vaet(@adapter.db(storage), v: 999) == []

        assert sorted(@adapter.scan_vaet(@adapter.db(storage), v: 101)) ==
                 sorted([{102, 20, 101, nil, nil}, {100, 30, 101, nil, nil}])
      end

      test "banco de base L com a transação L+1 completa antes da varredura lê consistente com L",
           %{storage: storage} do
        assert {:ok, 1} = @adapter.append(storage, [{100, 10, 1, true}])

        base_l = @adapter.db(storage)
        assert 1 == Enoch.DB.basis_t(base_l)

        assert {:ok, 2} =
                 @adapter.append(storage, [{100, 10, 1, false}, {100, 10, 2, true}])

        assert @adapter.scan_aevt(base_l, a: 10) == [{100, 10, 1, 1, true}]
        assert present(@adapter.db(storage), [10]) == [{100, 10, 2}]
      end

      # --- auxiliares da suíte ---------------------------------------------------

      defp sorted(rows), do: Enum.sort(rows)

      # O estado atual como as varreduras do presente o devolvem, sem `tx` e sem
      # `added`: os datoms vivos de cada atributo do caso.
      defp present(db, attrs) do
        attrs
        |> Enum.flat_map(fn a -> @adapter.scan_aevt(db, a: a) end)
        |> Enum.map(fn {e, a, v, _tx, _added} -> {e, a, v} end)
        |> Enum.sort()
      end

      # As linhas cruas do histórico, com `tx` e `added`, de uma base anterior ao
      # último `t` (numa base igual ao último `t` a varredura lê o estado atual).
      defp history(adapter, db, attrs) do
        Enum.flat_map(attrs, fn a -> adapter.scan_aevt(db, a: a) end)
      end

      # Modelo de referência do teste: vale o último operador por `(e, a, v)` com
      # `tx <= b`, e só os afirmados ficam. O avaliador resolve a visibilidade no
      # produto (D8); aqui é só o oráculo do reconstruído contra o gravado.
      defp reconstruct(rows) do
        rows
        |> Enum.sort_by(fn {e, a, v, tx, _added} -> {e, a, v, tx} end)
        |> Enum.reduce(%{}, fn {e, a, v, _tx, added}, live ->
          Map.put(live, {e, a, v}, added)
        end)
        |> Enum.filter(fn {_datom, added} -> added end)
        |> Enum.map(fn {datom, _added} -> datom end)
        |> Enum.sort()
      end
    end
  end
end
