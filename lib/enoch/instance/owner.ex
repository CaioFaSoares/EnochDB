defmodule Enoch.Instance.Owner do
  @moduledoc """
  O dono das tabelas da instância, separado do transactor (D18, D21).

  As tabelas nascem neste processo: o `Memory` cria as duas ETS e o contador em
  `adapter.open/1`, e o processo que chama `open/1` é dono delas. Com o dono fora
  do transactor, a queda do transactor não derruba as tabelas, e a estratégia
  `:rest_for_one` da árvore reinicia só ele (ver `Enoch.Instance.Supervisor`).

  O dono guarda o estado do adaptador e é ele que lê a base: `db/1` custa O(1) e
  não passa pela fila de escrita do transactor.

  ## A leitura e a entrega ao escritor são coisas diferentes

  `storage/1` é **só leitura**: devolve o estado do adaptador e nunca mexe nas
  tabelas. A recuperação da ADR-0003 é de `checkout/1`, a entrega do storage ao
  escritor novo, e só o `init` de `Enoch.Transactor` a chama — depois de uma queda,
  quando o transactor anterior já morreu (`:rest_for_one`) e ninguém escreve. Ler o
  storage durante uma transação não pode recuperar: o contador estaria ímpar e a
  recuperação apagaria as linhas de uma transação que quem chamou já viu gravada
  (issue #11, R03).

  ## A queda do dono para a instância

  O dono é filho `:temporary` e significativo da árvore, e a árvore sobe com
  `auto_shutdown: :any_significant`: perder o dono — e com ele as tabelas e o
  contador — derruba a instância em vez de reiniciar o dono com tabelas vazias e
  um `t` reutilizado (R06). Não há herdeiro: as tabelas não são entregues a outro
  processo, porque a instância inteira vai junto. A entrega real das tabelas, com o
  contador, é item de trabalho da s04/s05.

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
  O dono é temporário e significativo: a queda dele não o reinicia e derruba a
  instância (`auto_shutdown: :any_significant`, ver `Enoch.Instance.Supervisor`).

  Reiniciar o dono abriria tabelas novas e zeraria o `t`, reaproveitando os números
  de ordem de uma instância que perdeu o log (R06).
  """
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      restart: :temporary,
      significant: true,
      type: :worker
    }
  end

  @doc """
  O estado do adaptador, **sem** recuperar nada: é uma leitura das tabelas.

  O transactor não lê o storage por aqui no `init` — ele usa `checkout/1`, o único
  caminho que recupera. Esta chamada é para quem só precisa varrer ou conferir o
  estado — a subida, os testes e quem lê a base —, e é barata.

  Chamá-la durante uma transação é seguro: as varreduras usam o contador e a guarda
  da base, e nada aqui toca no histórico nem no estado atual. A recuperação de uma
  queda do transactor é de `checkout/1` (R03).
  """
  @spec storage(GenServer.server()) :: Enoch.Storage.t()
  def storage(owner), do: GenServer.call(owner, :storage, :infinity)

  @doc """
  Entrega o estado do adaptador ao escritor novo, recuperando antes se for preciso.

  É o papel de escritor: com a transação `t+1` morta no meio, o transactor novo só
  começa a escrever depois de as órfãs saírem, o estado atual ser reconstruído até
  `t` e o contador ser publicado em `2(t+1)` (R5, ADR-0003). Sem nada a recuperar a
  chamada é barata e não faz nada; a espera é a da recuperação, que é O(histórico) —
  um limite curto aqui abortaria o `init` do escritor no meio dela.

  Só `Enoch.Transactor.init/1` a chama: é o único momento em que o transactor
  anterior já morreu e nenhuma transação pode estar em curso. Devolve `{:ok, storage}`
  ou o erro do adaptador, que impede a subida do transactor.
  """
  @spec checkout(GenServer.server()) :: {:ok, Enoch.Storage.t()} | {:error, term()}
  def checkout(owner), do: GenServer.call(owner, :checkout, :infinity)

  @doc """
  O banco como valor na base publicada pelo contador (D16, D18).

  Custa O(1) e não passa pela fila de escrita. Quem já tem um banco como valor segue
  varrendo por ele, que a guarda do contador manda ao histórico quando a base muda
  (D18).
  """
  @spec db(GenServer.server()) :: Enoch.DB.t()
  def db(owner), do: GenServer.call(owner, :db)

  @impl true
  def init(opts) do
    adapter = Keyword.fetch!(opts, :adapter)
    storage_opts = Keyword.get(opts, :storage_opts, [])

    case adapter.open(storage_opts) do
      {:ok, storage} -> {:ok, %{adapter: adapter, storage: storage}}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call(:storage, _from, state), do: {:reply, state.storage, state}

  def handle_call(:checkout, _from, state) do
    case recover(state) do
      :ok -> {:reply, {:ok, state.storage}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:db, _from, state), do: {:reply, state.adapter.db(state.storage), state}

  # A recuperação é do adaptador — só ele sabe das tabelas e do contador — e o dono
  # só a chama quando ele a oferece. Um adaptador sem queda no meio da escrita não
  # tem o que recuperar. (`open/1` foi chamado no `init`, então o módulo já está
  # carregado quando o `function_exported?/3` pergunta.)
  defp recover(%{adapter: adapter, storage: storage}) do
    if function_exported?(adapter, :recover, 1), do: adapter.recover(storage), else: :ok
  end
end
