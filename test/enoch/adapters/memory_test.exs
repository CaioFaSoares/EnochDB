defmodule Enoch.Adapters.MemoryTest do
  @moduledoc """
  O que só o `Memory` tem: a obrigatoriedade do `max_memory` (D20), as duas
  tabelas ETS com o contador em `:atomics`, a ordem da escrita da D18 e o
  histórico conferido na própria tabela. O que é do contrato está na suíte
  `Enoch.Storage.ContractCase`, rodada em `test/enoch/storage/`.
  """

  use ExUnit.Case, async: true

  alias Enoch.Adapters.Memory
  alias Enoch.DB

  describe "open/1 e max_memory (D20, R16)" do
    test "não sobe sem max_memory" do
      assert {:error, {:missing_option, :max_memory}} = Memory.open([])
      assert {:error, {:missing_option, :max_memory}} = Memory.open(schema: [])
    end

    test "aceita :infinity" do
      assert {:ok, %{refs: {history, current, counter}}} =
               Memory.open(max_memory: :infinity)

      assert is_reference(history)
      assert is_reference(current)
      assert is_reference(counter)
    end

    test "aceita um inteiro em bytes (a cota e o alerta são da s05)" do
      assert {:ok, %{opts: opts}} = Memory.open(max_memory: 1_000_000)
      assert opts[:max_memory] == 1_000_000
    end

    test "recusa um valor que não é :infinity nem inteiro positivo" do
      assert {:error, {:invalid_option, {:max_memory, :zero}}} = Memory.open(max_memory: :zero)
      assert {:error, {:invalid_option, {:max_memory, 0}}} = Memory.open(max_memory: 0)
      assert {:error, {:invalid_option, {:max_memory, -1}}} = Memory.open(max_memory: -1)
    end
  end

  describe "estrutura (D18, R4)" do
    test "duas tabelas ETS do processo que chama, e o contador em :atomics" do
      assert {:ok, %{refs: {history, current, counter}} = storage} =
               Memory.open(max_memory: :infinity)

      assert :ordered_set == :ets.info(history, :type)
      assert :ordered_set == :ets.info(current, :type)
      assert self() == :ets.info(history, :owner)
      assert self() == :ets.info(current, :owner)
      assert is_reference(counter)
      assert 0 == :atomics.get(counter, 1)
      assert 0 == DB.basis_t(Memory.db(storage))
    end

    test "open/1 cria as tabelas no processo que a chama, sem presumir dono" do
      parent = self()

      pid =
        spawn(fn ->
          {:ok, %{refs: {history, _current, _counter}}} = Memory.open(max_memory: :infinity)
          send(parent, {:history, history})

          receive do
            :stop -> :ok
          end
        end)

      assert_receive {:history, history}
      assert ^pid = :ets.info(history, :owner)

      monitor = Process.monitor(pid)
      send(pid, :stop)
      assert_receive {:DOWN, ^monitor, :process, ^pid, _reason}

      assert :undefined == :ets.info(history)
    end
  end

  describe "a ordem da escrita (D18)" do
    test "contador para 2t+1, histórico, atual, contador para 2t+2" do
      assert {:ok, %{refs: {history, current, counter}} = storage} =
               Memory.open(max_memory: :infinity)

      datoms = [{100, 10, 1, true}, {101, 10, 2, true}]

      assert 1 == Memory.begin_tx(counter)
      assert 1 == :atomics.get(counter, 1)
      assert [] == :ets.tab2list(history)
      assert [] == :ets.tab2list(current)

      assert :ok == Memory.write_history(history, 1, datoms)

      assert [{{100, 10, 1, 1}, true}, {{101, 10, 2, 1}, true}] == :ets.tab2list(history)
      assert [] == :ets.tab2list(current)

      assert :ok == Memory.apply_current(current, datoms)
      assert [{{100, 10, 1}}, {{101, 10, 2}}] == :ets.tab2list(current)

      assert :ok == Memory.publish_tx(counter, 1)
      assert 2 == :atomics.get(counter, 1)
      assert 1 == DB.basis_t(Memory.db(storage))
    end
  end

  describe "append/2 e o histórico" do
    test "grava a transação, publica a base e devolve o t" do
      assert {:ok, %{refs: {history, current, counter}} = storage} =
               Memory.open(max_memory: :infinity)

      assert {:ok, 1} = Memory.append(storage, [{100, 10, 1, true}])
      assert {:ok, 2} = Memory.append(storage, [{100, 10, 1, false}, {100, 10, 2, true}])

      assert 4 == :atomics.get(counter, 1)
      assert 2 == DB.basis_t(Memory.db(storage))

      assert [{{100, 10, 1, 1}, true}, {{100, 10, 1, 2}, false}, {{100, 10, 2, 2}, true}] ==
               :ets.tab2list(history)

      assert [{{100, 10, 2}}] == :ets.tab2list(current)
    end

    test "afirmar, retrair e reafirmar o mesmo (e, a, v) deixa três linhas no histórico" do
      assert {:ok, %{refs: {history, current, _counter}} = storage} =
               Memory.open(max_memory: :infinity)

      assert {:ok, 1} = Memory.append(storage, [{100, 10, 7, true}])
      assert {:ok, 2} = Memory.append(storage, [{100, 10, 7, false}])
      assert {:ok, 3} = Memory.append(storage, [{100, 10, 7, true}])

      assert 3 == :ets.info(history, :size)

      assert [{{100, 10, 7, 1}, true}, {{100, 10, 7, 2}, false}, {{100, 10, 7, 3}, true}] ==
               :ets.tab2list(history)

      assert [{{100, 10, 7}}] == :ets.tab2list(current)
    end
  end

  describe "a conferência do passo 2 (R04)" do
    test "um leitor durante a reconstrução nunca aceita uma varredura do presente pela metade" do
      assert {:ok, %{refs: {_history, current, counter}} = storage} =
               Memory.open(max_memory: :infinity)

      entidades = 60_000
      assert {:ok, 1} = Memory.append(storage, for(e <- 1..entidades, do: {e, 10, e, true}))

      # O presente diverge do histórico — uma linha que o log não tem —, e a
      # reconstrução do passo 2 vai apagá-lo e refazer a tabela inteira.
      assert true = :ets.insert(current, {{entidades + 1, 10, 0}})
      assert 2 == :atomics.get(counter, 1)

      db = Memory.db(storage)
      assert 1 == DB.basis_t(db)

      pai = self()
      leitor = spawn(fn -> varrer(pai, db) end)

      assert :ok = Memory.verify(storage)

      # A reconstrução é uma transação vazia: o contador foi a `2b+1` antes de tocar
      # no presente e foi publicado em `2(b+1)`.
      assert 4 == :atomics.get(counter, 1)
      assert 2 == DB.basis_t(Memory.db(storage))

      Process.sleep(10)
      send(leitor, :pare)
      observacoes = observacoes([])

      # Antes da reconstrução o leitor vê o presente com a linha adulterada; da
      # reconstrução em diante, o histórico na mesma base, com o estado completo. O
      # que ele nunca vê é a tabela pela metade.
      refute observacoes == [], "o leitor não varreu nada"
      assert Enum.any?(observacoes, & &1.historico), "o leitor não leu o histórico"

      assert Enum.all?(observacoes, &(&1.contagem in [entidades, entidades + 1])),
             "o leitor aceitou uma varredura pela metade: #{inspect(Enum.map(observacoes, & &1.contagem))}"

      assert Enum.any?(observacoes, &(&1.historico and &1.contagem == entidades))

      # Depois da reconstrução o presente é de novo a projeção dos vivos.
      assert Memory.scan_aevt(Memory.db(storage), a: 10) |> length() == entidades
      refute :ets.member(current, {entidades + 1, 10, 0})
    end
  end

  # O leitor do passo 2: varre a base 1 sem parar até o `:pare` e manda cada
  # varredura com a contagem e se ela saiu do histórico.
  defp varrer(pai, db) do
    rows = Memory.scan_aevt(db, a: 10)

    send(
      pai,
      {:varredura,
       %{contagem: length(rows), historico: Enum.any?(rows, fn {_e, _a, _v, tx, _} -> tx end)}}
    )

    receive do
      :pare -> send(pai, :fim)
    after
      0 -> varrer(pai, db)
    end
  end

  defp observacoes(acc) do
    receive do
      {:varredura, observacao} -> observacoes([observacao | acc])
      :fim -> Enum.reverse(acc)
    after
      5_000 -> flunk("o leitor não terminou")
    end
  end
end
