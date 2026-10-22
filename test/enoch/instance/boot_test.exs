defmodule Enoch.BootTest.Greet do
  @moduledoc false

  @behaviour Enoch.Tx.Function

  @impl true
  def call(args), do: args
end

defmodule Enoch.BootTest.GreetTwo do
  @moduledoc false

  @behaviour Enoch.Tx.Function

  @impl true
  def call(args), do: args
end

defmodule Enoch.BootTest.Functions do
  @moduledoc false

  def functions, do: [{:"app/greet", Enoch.BootTest.Greet}]
end

defmodule Enoch.BootTest.Rules do
  @moduledoc false

  def rules, do: [%{name: :adult, args: [:e], body: []}]
end

defmodule Enoch.BootTest.RulesTwo do
  @moduledoc false

  def rules, do: [%{name: :adult, args: [:e], body: []}]
end

defmodule Enoch.BootTest.Schema do
  @moduledoc false

  def schema, do: [%{name: :"person/name", type: :string}]
end

defmodule Enoch.Instance.BootTest do
  @moduledoc """
  A sequência de subida em sete passos (D34, R31) e os critérios da F7 (#8) que
  ficaram sem teste na s01 (issue #11, R07):

  1. um layout mais novo impede a subida e, durante ela, nenhuma escrita externa
     passa — a admissão nasce fechada (R02);
  2. um estado atual adulterado é reconstruído no passo 2;
  3. um `verify/1` que devolve erro interrompe a subida (R05);
  4. dois módulos com o mesmo nome de função, ou de regra, impedem a subida;
  5. a subida emite `[:enoch, :boot]` com o `basis_t` da instância;
  6. módulos de schema, de funções e de regras definidos fora do pacote entram no
     registro do passo 4.

  Dois caminhos: `Enoch.start_link/1`, o caminho público, para o que impede a
  subida; e a árvore de `Enoch.Instance.Supervisor.start_link/1` seguida de
  `Enoch.Instance.Boot.run/2`, para observar o registro e o estado antes e depois
  da subida. O adaptador dos passos 1 e 2 é o `Enoch.Test.BootAdapter`, de
  `test/support/`, que segura a subida até o teste olhar a instância e reporta a
  versão do layout e o resultado de `verify/1` que o teste pedir.

  Referências: `docs/_sprints/s01-nucleo-enoch/03_spec/handovers/spec.md` (R17, R24,
  R30, R31), ADR-0008 e a issue #8.
  """

  use ExUnit.Case, async: false

  alias Enoch.Adapters.Memory
  alias Enoch.BootTest.{Functions, Greet, GreetTwo, Rules, RulesTwo, Schema}
  alias Enoch.DB
  alias Enoch.Instance.{Admission, Boot, Owner}
  alias Enoch.Instance.Supervisor, as: Instance
  alias Enoch.Test.BootAdapter

  @storage_opts [max_memory: :infinity]
  @attr 10
  @handler {__MODULE__, :boot}

  describe "layout e admissão (R02, R31)" do
    test "um layout mais novo impede a subida e nenhuma escrita externa passa durante ela" do
      nome = unico()
      pai = self()

      subida =
        Task.async(fn ->
          Enoch.start_link(
            name: nome,
            adapter: BootAdapter,
            storage_opts: @storage_opts ++ [layout_version: 99, boot_probe: pai]
          )
        end)

      assert_receive {:boot_probe, subidor}, 5_000

      # A árvore está de pé — dono e admissão — e a subida está no passo 1. A
      # admissão nasceu fechada, então a escrita externa é rejeitada antes de
      # qualquer transactor existir.
      assert Admission.status(nome) == :closed
      assert {:error, :admission_closed} = Enoch.transact(nome, [[:add, 1, @attr, 7]])
      assert DB.basis_t(Enoch.db(nome)) == 0

      send(subidor, :continue)

      assert {:error, {:layout_too_new, 99, 0}} = Task.await(subida, 5_000)

      # A subida falhou e derrubou a árvore: a instância não está no ar e a tabela
      # do único datom jamais recebeu a escrita rejeitada.
      assert_raise ArgumentError, ~r/is not running/, fn ->
        Enoch.transact(nome, [[:add, 2, @attr, 8]])
      end
    end

    test "um verify/1 com erro interrompe a subida" do
      nome = unico()

      assert {:error, :diverged} =
               Enoch.start_link(
                 name: nome,
                 adapter: BootAdapter,
                 storage_opts: @storage_opts ++ [verify: {:error, :diverged}]
               )

      assert_raise ArgumentError, ~r/is not running/, fn -> Enoch.db(nome) end
    end
  end

  describe "o passo 2 e a telemetria (R04, R17, R31)" do
    test "um estado atual adulterado é reconstruído e o evento de subida leva a base" do
      nome = unico()
      {:ok, sup} = Instance.start_link(name: nome, adapter: Memory, storage_opts: @storage_opts)
      on_exit(fn -> parar(sup) end)

      owner = Instance.owner(nome)
      storage = Owner.storage(owner)

      assert {:ok, 1} =
               Memory.append(storage, [{100, @attr, 1, true}, {101, @attr, 2, true}])

      %{refs: {_history, current, _counter}} = storage
      assert true = :ets.insert(current, {{9, @attr, 9}})

      anexar_telemetria()

      assert {:ok, _registro} = Boot.run(nome, adapter: Memory, storage_opts: @storage_opts)

      # O presente foi reconstruído do histórico: a linha adulterada sumiu e o que
      # foi gravado ficou. A reconstrução é uma transação vazia — publicada em 2,
      # depois da base 1 —, e é ela que o evento carrega.
      refute :ets.member(current, {9, @attr, 9})

      assert Memory.scan_aevt(Memory.db(storage), a: @attr) == [
               {100, @attr, 1, nil, nil},
               {101, @attr, 2, nil, nil}
             ]

      assert DB.basis_t(Memory.db(storage)) == 2

      assert_receive {:boot, [:enoch, :boot], %{basis_t: 2}, %{instance: ^nome}}, 5_000

      # O passo 3 iniciou o transactor, o passo 7 abriu a admissão e a escrita
      # seguinte é a `t+1` da base publicada.
      assert is_pid(GenServer.whereis(Instance.transactor(nome)))
      assert Admission.status(nome) == :open
      assert {:ok, 3} = Enoch.transact(nome, [[:add, 200, @attr, 3]])
    end
  end

  describe "o passo 4 (R24)" do
    test "dois módulos com o mesmo nome de função impedem a subida" do
      nome = unico()

      assert {:error, {:duplicate_function, :"app/greet", Greet, GreetTwo}} =
               Enoch.start_link(
                 name: nome,
                 adapter: Memory,
                 storage_opts: @storage_opts,
                 functions: [{:"app/greet", Greet}, {:"app/greet", GreetTwo}]
               )
    end

    test "dois módulos com o mesmo nome de regra impedem a subida" do
      nome = unico()

      assert {:error, {:duplicate_rule, :adult, Rules, RulesTwo}} =
               Enoch.start_link(
                 name: nome,
                 adapter: Memory,
                 storage_opts: @storage_opts,
                 rules: [Rules, RulesTwo]
               )
    end

    test "módulos de schema, funções e regras definidos fora do pacote entram no registro" do
      nome = unico()
      {:ok, sup} = Instance.start_link(name: nome, adapter: Memory, storage_opts: @storage_opts)
      on_exit(fn -> parar(sup) end)

      anexar_telemetria()

      assert {:ok, registro} =
               Boot.run(nome,
                 adapter: Memory,
                 storage_opts: @storage_opts,
                 schema: [Schema],
                 functions: [Functions],
                 rules: [Rules]
               )

      assert registro.schema == [Schema]
      assert registro.functions == %{:"app/greet" => Greet}
      assert registro.rules == %{adult: Rules}

      assert_receive {:boot, [:enoch, :boot], %{basis_t: 0}, %{instance: ^nome}}, 5_000
    end
  end

  defp anexar_telemetria do
    :telemetry.attach(
      @handler,
      Enoch.Telemetry.boot_event(),
      &__MODULE__.handle_boot/4,
      self()
    )

    on_exit(fn -> :telemetry.detach(@handler) end)
  end

  @doc false
  def handle_boot(evento, medidas, metadados, pid) do
    send(pid, {:boot, evento, medidas, metadados})
  end

  defp unico, do: {__MODULE__, System.unique_integer([:positive])}

  defp parar(sup) do
    try do
      if Process.alive?(sup), do: Supervisor.stop(sup, :normal, 5_000)
    catch
      :exit, _motivo -> :ok
    end
  end
end
