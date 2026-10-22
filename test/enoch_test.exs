defmodule EnochTest do
  @moduledoc """
  A API pública de uma instância, pelo caminho de fora: ler de volta um `add`
  seguido de `retract` feito por `Enoch.transact/2` (R11, issue #11 R09), embutir a
  instância num supervisor da aplicação com `{Enoch, opts}` (R14) e a falha única de
  `transact/2` e `db/1` numa instância desconhecida (R15).

  A leitura de volta usa o adaptador direto porque a API de consulta é da s03: o
  presente e a base anterior são as varreduras do `Enoch.Storage`. O presente é o
  banco como valor da base publicada; a base anterior é um valor capturado antes da
  retração — a varredura dele sai pelo histórico, com `tx` e `added`.

  Referências: `docs/_sprints/s01-nucleo-enoch/03_spec/handovers/spec.md` (R11, R30),
  ADR-0007 e a issue #5.
  """

  use ExUnit.Case, async: false

  alias Enoch.Adapters.Memory
  alias Enoch.DB

  @storage_opts [max_memory: :infinity]
  @attr 10

  describe "add e retract pelo caminho público (R11, R09)" do
    test "o add e o retract são lidos no presente e na base anterior" do
      nome = subir()

      assert {:ok, 1} = Enoch.transact(nome, [[:add, 100, @attr, 7]])
      base_1 = Enoch.db(nome)

      assert 1 == DB.basis_t(base_1)
      assert Memory.scan_aevt(base_1, a: @attr) == [{100, @attr, 7, nil, nil}]

      assert {:ok, 2} = Enoch.transact(nome, [[:retract, 100, @attr, 7]])
      base_2 = Enoch.db(nome)

      assert 2 == DB.basis_t(base_2)

      # No presente o datom retraído não existe mais.
      assert Memory.scan_aevt(base_2, a: @attr) == []

      # Uma transação posterior faz a base 2 virar passado: a varredura lê o
      # histórico, com o add e o retract, na ordem e com o operador de cada um.
      assert {:ok, 3} = Enoch.transact(nome, [[:add, 200, @attr, 8]])

      assert Memory.scan_aevt(base_2, a: @attr) == [
               {100, @attr, 7, 1, true},
               {100, @attr, 7, 2, false}
             ]

      # E a base 1 mostra só a afirmação, como era antes da retração.
      assert Memory.scan_aevt(base_1, a: @attr) == [{100, @attr, 7, 1, true}]

      assert Memory.scan_aevt(Enoch.db(nome), a: @attr) == [{200, @attr, 8, nil, nil}]
    end
  end

  describe "child_spec/1 (R14)" do
    test "{Enoch, opts} é filho de um supervisor da aplicação" do
      nome = {__MODULE__, :embutida}

      spec = Enoch.child_spec(name: nome, adapter: Memory, storage_opts: @storage_opts)
      assert spec.id == {Enoch, nome}
      assert spec.type == :supervisor

      {:ok, sup} =
        Supervisor.start_link(
          [{Enoch, [name: nome, adapter: Memory, storage_opts: @storage_opts]}],
          strategy: :one_for_one
        )

      on_exit(fn -> parar(sup) end)

      assert [{id, instancia, :supervisor, _modulos}] = Supervisor.which_children(sup)
      assert id == {Enoch, nome}
      assert is_pid(instancia)
      assert Process.alive?(instancia)

      assert {:ok, 1} = Enoch.transact(nome, [[:add, 1, @attr, 7]])
      assert 1 == DB.basis_t(Enoch.db(nome))
    end
  end

  describe "instância desconhecida (R15)" do
    test "transact/2 e db/1 falham do mesmo jeito" do
      nome = {__MODULE__, :nao_sobe}

      erro_transact =
        assert_raise ArgumentError, fn -> Enoch.transact(nome, [[:add, 1, @attr, 7]]) end

      erro_db = assert_raise ArgumentError, fn -> Enoch.db(nome) end

      assert Exception.message(erro_transact) == Exception.message(erro_db)
      assert Exception.message(erro_db) =~ inspect(nome)
    end
  end

  defp subir do
    nome = {__MODULE__, System.unique_integer([:positive])}

    assert {:ok, sup} =
             Enoch.start_link(name: nome, adapter: Memory, storage_opts: @storage_opts)

    on_exit(fn -> parar(sup) end)
    nome
  end

  defp parar(sup) do
    try do
      if Process.alive?(sup), do: Supervisor.stop(sup, :normal, 5_000)
    catch
      :exit, _motivo -> :ok
    end
  end
end
