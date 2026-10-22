defmodule Enoch.Instance.OwnerTest do
  @moduledoc """
  O dono das tabelas: a leitura do storage não recupera (R03) e a queda do dono
  derruba a instância (R06) — as duas correções da issue #11 no
  `Enoch.Instance.Owner`.

  A primeira prova que `Owner.storage/1` é só leitura: com uma transação grande em
  curso — o histórico já com parte das linhas, o estado atual com outra, o contador
  ímpar —, ler o storage não pode rodar a recuperação, que apagaria as linhas da
  transação que quem chamou viu gravar. A segunda prova que perder o dono não
  reinicia a árvore com tabelas vazias: o supervisor da instância não recebe as
  tabelas (`ETS-TRANSFER`) e a instância inteira sai do ar.

  Referências: `docs/_sprints/s01-nucleo-enoch/03_spec/handovers/spec.md` (R5),
  `docs/adr/0003-*.md` e `docs/adr/0004-*.md`.
  """

  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Enoch.Adapters.Memory
  alias Enoch.DB
  alias Enoch.Instance.{Admission, Owner}
  alias Enoch.Instance.Supervisor, as: Instance

  @storage_opts [max_memory: :infinity]
  @attr 10

  describe "storage/1 é leitura (R03)" do
    test "ler o storage com uma transação em curso deixa histórico e presente completos" do
      nome = unico()
      {:ok, sup} = Enoch.start_link(name: nome, adapter: Memory, storage_opts: @storage_opts)
      on_exit(fn -> parar(sup) end)

      %{refs: {history, current, counter}} = storage = Owner.storage(Instance.owner(nome))

      # Uma transação grande o bastante para a leitura do storage cair no meio dela.
      datoms = for e <- 1..100_000, do: [:add, e, @attr, e]
      em_curso = Task.async(fn -> Enoch.transact(nome, datoms) end)

      assert aguardar(fn -> rem(:atomics.get(counter, 1), 2) == 1 end)
      assert :atomics.get(counter, 1) > 0

      # A leitura do storage no meio da escrita: não recupera, não apaga linha.
      assert %{refs: {^history, ^current, ^counter}} = Owner.storage(Instance.owner(nome))

      assert {:ok, 1} = Task.await(em_curso, 60_000)

      # A transação que quem chamou viu gravar está inteira: as 100 000 linhas de
      # histórico e as 100 000 do presente, e a base publicada.
      assert 100_000 == :ets.info(history, :size)
      assert 100_000 == :ets.info(current, :size)
      assert 2 == :atomics.get(counter, 1)
      assert 1 == DB.basis_t(Memory.db(storage))
    end
  end

  describe "a queda do dono (R06)" do
    test "perder o dono derruba a instância em vez de reiniciá-la com tabelas vazias" do
      Process.flag(:trap_exit, true)
      nome = unico()
      {:ok, sup} = Enoch.start_link(name: nome, adapter: Memory, storage_opts: @storage_opts)

      assert {:ok, 1} = Enoch.transact(nome, [[:add, 1, @attr, 7]])
      assert 1 == DB.basis_t(Enoch.db(nome))

      owner = GenServer.whereis(Instance.owner(nome))
      monitor = Process.monitor(sup)

      log =
        capture_log(fn ->
          Process.exit(owner, :kill)
          assert_receive {:DOWN, ^monitor, :process, ^sup, :shutdown}, 5_000
        end)

      # O supervisor da instância não recebeu as tabelas: não há `ETS-TRANSFER` nem
      # mensagem inesperada no supervisor.
      refute log =~ "ETS-TRANSFER"
      refute log =~ "unexpected message"

      refute Process.alive?(sup)
      assert GenServer.whereis(Instance.owner(nome)) == nil

      # A instância não está no ar — não há árvore nova com tabelas vazias e o `t`
      # reutilizado —, e o nome responde como uma instância desconhecida. A limpeza
      # da chave do `Registry` é assíncrona, então a espera é a de ela sumir.
      assert_raise ArgumentError, ~r/is not running/, fn -> Enoch.db(nome) end
      assert aguardar(fn -> GenServer.whereis(Instance.admission(nome)) == nil end)
      assert_raise ArgumentError, fn -> Admission.status(nome) end
    end
  end

  defp unico, do: {__MODULE__, System.unique_integer([:positive])}

  defp aguardar(condicao, tentativas \\ 2_000) do
    cond do
      condicao.() ->
        true

      tentativas == 0 ->
        false

      true ->
        Process.sleep(1)
        aguardar(condicao, tentativas - 1)
    end
  end

  defp parar(sup) do
    try do
      if Process.alive?(sup), do: Supervisor.stop(sup, :normal, 5_000)
    catch
      :exit, _motivo -> :ok
    end
  end
end
