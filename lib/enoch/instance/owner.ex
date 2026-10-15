defmodule Enoch.Instance.Owner do
  @moduledoc """
  O dono das tabelas da instância, separado do transactor (D18, D21).

  As tabelas nascem neste processo: o `Memory` cria as duas ETS e o contador em
  `adapter.open/1`, e o processo que chama `open/1` é dono delas. Com o dono fora
  do transactor, a queda do transactor não derruba as tabelas, e a estratégia
  `:rest_for_one` da árvore reinicia só ele (ver `Enoch.Instance.Supervisor`).

  O dono guarda o estado do adaptador e é ele que lê a base: `db/1` custa O(1) e
  não passa pela fila de escrita do transactor. A recuperação da ADR-0003 roda na
  entrega do storage — `storage/1` é o que o transactor lê no `init`, então o
  escritor novo só recebe o estado depois de ele estar limpo, e o `call` o segura
  até a recuperação terminar. As tabelas nascem aqui, com o `:heir` no supervisor
  da instância: a queda do transactor não as leva.

  Referências: `docs/arquitetura.md` (`instance/owner.ex`), ADR-0003, ADR-0004,
  ADR-0008 e a spec em `docs/_sprints/s01-nucleo-enoch/03_spec/handovers/spec.md`
  (R5, R30).
  """

  use GenServer

  @doc """
  Sobe o dono e abre o storage no próprio processo.

  Opções: `:name` (obrigatória, o nome registrado), `:adapter` (obrigatória) e
  `:storage_opts` (as opções de `adapter.open/1`). Um erro do adaptador, como a
  falta do `max_memory` do `Memory` (D20), impede a subida da instância.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))
  end

  @doc """
  O estado do adaptador, que o transactor usa para gravar.

  É a entrega do papel de escritor, e por isso ela recupera antes de responder: com
  a transação `t+1` morta no meio, o transactor novo só começa a escrever depois de
  as órfãs saírem, o estado atual ser reconstruído até `t` e o contador ser
  publicado em `2(t+1)` (R5, ADR-0003). Sem nada a recuperar a chamada é barata e
  não faz nada; a espera é a da recuperação, que é O(histórico) — um limite curto
  aqui abortaria o `init` do escritor no meio dela.
  """
  @spec storage(GenServer.server()) :: Enoch.Storage.t()
  def storage(owner), do: GenServer.call(owner, :storage, :infinity)

  @doc """
  O banco como valor na base publicada pelo contador (D16, D18).

  Custa O(1) e não passa pela fila de escrita. Durante uma recuperação (ver
  `storage/1`) o dono está ocupado e esta chamada espera a vez dele; quem já tem um
  banco como valor segue varrendo por ele, que a guarda do contador manda ao
  histórico quando a base muda (D18).
  """
  @spec db(GenServer.server()) :: Enoch.DB.t()
  def db(owner), do: GenServer.call(owner, :db)

  @impl true
  def init(opts) do
    adapter = Keyword.fetch!(opts, :adapter)
    storage_opts = Keyword.get(opts, :storage_opts, [])

    case adapter.open(heir_opts(storage_opts)) do
      {:ok, storage} -> {:ok, %{adapter: adapter, storage: storage}}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call(:storage, _from, state) do
    :ok = recover(state)
    {:reply, state.storage, state}
  end

  def handle_call(:db, _from, state), do: {:reply, state.adapter.db(state.storage), state}

  # A recuperação é do adaptador — só ele sabe das tabelas e do contador — e o dono
  # só a chama quando ele a oferece. Um adaptador sem queda no meio da escrita não
  # tem o que recuperar. (`open/1` foi chamado no `init`, então o módulo já está
  # carregado quando o `function_exported?/3` pergunta.)
  defp recover(%{adapter: adapter, storage: storage}) do
    if function_exported?(adapter, :recover, 1), do: adapter.recover(storage), else: :ok
  end

  # O `:heir` das tabelas: o supervisor da instância, o processo que sobrevive à
  # queda do dono e do transactor. `$ancestors` é o caminho do OTP para o pai de um
  # processo de `proc_lib`; sem ele — um dono que sobe direto, por exemplo — as
  # tabelas ficam sem heir e morrem com o dono. Um `:heir` já nas `storage_opts`
  # manda.
  defp heir_opts(storage_opts) do
    case parent() do
      nil -> storage_opts
      parent -> Keyword.put_new(storage_opts, :heir, parent)
    end
  end

  defp parent do
    case Process.get(:"$ancestors") do
      [parent | _] when is_pid(parent) -> parent
      _ -> nil
    end
  end
end
