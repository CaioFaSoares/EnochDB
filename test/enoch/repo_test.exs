defmodule Enoch.RepoTest do
  @moduledoc """
  O esqueleto do `use Enoch.Repo`: a camada fina que delega à API funcional por
  nome de instância, sem lógica própria (R30, D32, ADR-0007).

  O que o teste prova é a equivalência dos dois caminhos: o módulo que faz
  `use Enoch.Repo` e a chamada funcional pelo nome da instância, com as mesmas
  operações, dão o mesmo resultado em `transact` e em `db` (issue #9).

  Os dois caminhos rodam em instâncias gêmeas — a mesma sequência de operações, uma
  de cada lado —, porque repetir a transação na mesma instância grava um `t` novo.
  As instâncias sobem com `:memory:` e não exigem módulo próprio (R30); o
  `Enoch.RepoTest.Db` é a aplicação de exemplo, cujo módulo é o nome da instância.

  Referências: `docs/_sprints/s01-nucleo-enoch/03_spec/handovers/spec.md` (R30),
  `docs/adr/0007-*.md` e `docs/arquitetura.md` (`repo.ex`).
  """

  use ExUnit.Case, async: true

  alias Enoch.Adapters.Memory
  alias Enoch.DB

  @storage_opts [max_memory: :infinity]
  @attr 10

  defmodule Db do
    @moduledoc """
    A aplicação de exemplo: o módulo do repo é o nome da instância (ADR-0007).
    """

    use Enoch.Repo
  end

  describe "use Enoch.Repo" do
    test "não aceita opções nesta sprint" do
      assert_raise ArgumentError, ~r/não aceita opções nesta sprint/, fn ->
        Code.compile_string("""
        defmodule Enoch.RepoTest.ComOpcoes do
          use Enoch.Repo, adapter: Enoch.Adapters.Memory
        end
        """)
      end
    end
  end

  describe "transact/1" do
    test "o repo e a chamada funcional dão o mesmo resultado" do
      subir(Db)
      outra = subir({__MODULE__, :funcional})

      operacoes = [
        [[:add, 1, @attr, 10], [:add, 2, @attr, 20]],
        [[:retract, 1, @attr, 10]],
        [[:add, 2, @attr, 30]]
      ]

      for {ops, i} <- Enum.with_index(operacoes) do
        assert Db.transact(ops) == Enoch.transact(outra, ops),
               "a operação #{i} divergiu entre o repo e a chamada funcional"

        assert DB.basis_t(Db.db()) == DB.basis_t(Enoch.db(outra)),
               "a base divergiu depois da operação #{i}"
      end

      # A operação inválida também é a mesma nos dois caminhos: a camada não
      # corrige nem traduz o que vem de baixo.
      assert Db.transact([[:add, 1]]) == Enoch.transact(outra, [[:add, 1]])

      assert DB.basis_t(Db.db()) == 3
    end
  end

  describe "db/0" do
    test "o repo e a chamada funcional dão o mesmo banco como valor" do
      nome = subir(Db)

      assert {:ok, 1} = Enoch.transact(nome, [[:add, 1, @attr, 10]])
      assert Db.db() == Enoch.db(nome)
      assert 1 == DB.basis_t(Db.db())

      assert {:ok, 2} = Db.transact([[:add, 2, @attr, 20]])
      assert Db.db() == Enoch.db(nome)
      assert 2 == DB.basis_t(Db.db())
    end
  end

  defp subir(nome) do
    assert {:ok, sup} =
             Enoch.start_link(name: nome, adapter: Memory, storage_opts: @storage_opts)

    on_exit(fn -> parar(sup) end)
    nome
  end

  defp parar(sup) do
    try do
      if Process.alive?(sup), do: Supervisor.stop(sup, :normal, 5_000)
    catch
      :exit, _reason -> :ok
    end
  end
end
