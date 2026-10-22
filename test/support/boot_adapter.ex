defmodule Enoch.Test.BootAdapter do
  @moduledoc """
  Adaptador de teste dos passos 1 e 2 da subida: um `Enoch.Adapters.Memory` com a
  versão do layout e o resultado de `verify/1` controlados pelas opções.

  Existe para `test/enoch/instance/boot_test.exs` provar, pelo caminho de fora, que
  um layout mais novo impede a subida, que uma escrita externa não passa durante a
  subida e que um `verify/1` com erro a interrompe (R02, R05, R31). As opções do
  adaptador saem das `storage_opts` antes de elas irem para o `Memory`:

    - `:layout_version` — a versão que `layout_version/1` reporta;
    - `:verify` — `{:error, motivo}` para `verify/1` falhar; sem ela, vale o
      `Memory.verify/1`;
    - `:boot_probe` — um pid que recebe `{:boot_probe, pid_de_quem_subiu}`; a
      subida espera `:continue` por até cinco segundos, o que deixa o teste observar
      a instância no meio da subida.

  O resto do contrato delega ao `Memory`; o storage entregue é um mapa com o do
  `Memory` e as opções da subida. Não entra no pacote publicado (`mix.exs`,
  `elixirc_paths/1`).
  """

  @behaviour Enoch.Storage

  alias Enoch.Adapters.Memory

  @probe_timeout 5_000

  @impl Enoch.Storage
  def open(opts) do
    {boot_opts, storage_opts} = Keyword.split(opts, [:layout_version, :verify, :boot_probe])

    with {:ok, memory} <- Memory.open(storage_opts) do
      {:ok, %{memory: memory, boot: boot_opts}}
    end
  end

  @impl Enoch.Storage
  def db(%{memory: memory}), do: Memory.db(memory)

  @impl Enoch.Storage
  def append(%{memory: memory}, datoms), do: Memory.append(memory, datoms)

  @impl Enoch.Storage
  def rows_read(%{memory: memory}), do: Memory.rows_read(memory)

  @impl Enoch.Storage
  def scan_eavt(db, opts), do: Memory.scan_eavt(db, opts)

  @impl Enoch.Storage
  def scan_aevt(db, opts), do: Memory.scan_aevt(db, opts)

  @impl Enoch.Storage
  def scan_avet(db, opts), do: Memory.scan_avet(db, opts)

  @impl Enoch.Storage
  def scan_vaet(db, opts), do: Memory.scan_vaet(db, opts)

  @impl Enoch.Storage
  def recover(%{memory: memory}), do: Memory.recover(memory)

  @impl Enoch.Storage
  def layout_version(%{memory: memory, boot: boot}) do
    wait_for_probe(boot)
    Keyword.get(boot, :layout_version) || Memory.layout_version(memory)
  end

  @impl Enoch.Storage
  def verify(%{memory: memory, boot: boot}) do
    case Keyword.get(boot, :verify) do
      nil -> Memory.verify(memory)
      {:error, reason} -> {:error, reason}
    end
  end

  defp wait_for_probe(boot) do
    case Keyword.get(boot, :boot_probe) do
      nil ->
        :ok

      pid ->
        send(pid, {:boot_probe, self()})

        receive do
          :continue -> :ok
        after
          @probe_timeout -> :ok
        end
    end
  end
end
