defmodule Enoch.Instance.Supervisor do
  @moduledoc """
  Árvore de supervisão de uma instância do banco (D32, D21, D27, D34).

  Cada instância — o nome que o chamador dá em `Enoch.start_link/1` — sobe a
  própria árvore, e duas instâncias com nomes diferentes convivem no mesmo nó sem
  compartilhar estado: cada uma abre as próprias tabelas no processo dono
  (`Enoch.Instance.Owner`), tem a própria admissão
  (`Enoch.Instance.Admission`) e o próprio transactor (`Enoch.Transactor`).

  A árvore sobe com **dois** filhos: o dono e a admissão. O transactor não nasce
  com ela: o passo 3 da subida (`Enoch.Instance.Boot`, D34, R31) o inicia por
  `Supervisor.start_child/2`, depois de o passo 1 conferir o layout e o passo 2
  conferir o estado atual — e com a admissão fechada, que o `init` da admissão já
  garante desde a subida da árvore. Assim nenhuma escrita externa passa entre a
  árvore de pé e o passo 7 (issue #11, R02).

  A estratégia é `:rest_for_one`, na ordem dono, admissão e transactor. A queda do
  transactor reinicia só ele: o dono segue vivo com as tabelas e a admissão segue
  com o contador, cujo `init` novo zera (D27) — a recuperação da ADR-0003 depende
  disso. O dono é `:temporary` e significativo e a árvore usa
  `auto_shutdown: :any_significant`: perder o dono derruba a instância em vez de
  reabrir tabelas vazias e reutilizar o `t` (R06).

  Os filhos são registrados no `Registry` global da aplicação
  (`Enoch.InstanceRegistry`, ver `Enoch.Application`), com o nome da instância na
  chave. `owner/1`, `admission/1` e `transactor/1` devolvem esses nomes e `name/1`
  devolve o da própria árvore. O nome da instância pode ser qualquer termo; o
  módulo de um `use Enoch.Repo` é o uso típico (ADR-0007).

  Referências: `docs/arquitetura.md` (`instance/supervisor.ex`), ADR-0003,
  ADR-0004, ADR-0007, ADR-0008 e a spec em
  `docs/_sprints/s01-nucleo-enoch/03_spec/handovers/spec.md` (R13, R30, R31).
  """

  use Supervisor

  alias Enoch.Instance.Admission

  @registry Enoch.InstanceRegistry

  @doc """
  Sobe a árvore da instância.

  Opções: `:name` (obrigatória, o nome da instância), `:adapter` (obrigatória, o
  módulo que implementa `Enoch.Storage`), `:storage_opts` (opcional, as opções
  que vão para `adapter.open/1` — no `Memory`, o `max_memory` obrigatório, D20) e
  `:admission` (opcional, as opções da admissão limitada: `:limit` e `:status`, ver
  `Enoch.Instance.Admission`).

  A árvore sobe o dono e a admissão; o transactor entra no passo 3 da subida.
  """
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    instance = Keyword.fetch!(opts, :name)

    Supervisor.start_link(__MODULE__, opts, name: name(instance))
  end

  @doc "O nome registrado da árvore de uma instância."
  @spec name(term()) :: {:via, module(), term()}
  def name(instance), do: via(:supervisor, instance)

  @doc "O nome registrado do dono das tabelas de uma instância."
  @spec owner(term()) :: {:via, module(), term()}
  def owner(instance), do: via(:owner, instance)

  @doc """
  O nome registrado da admissão de uma instância.

  Vem de `Enoch.Instance.Admission.name/1`, porque é lá que a admissão registra o
  contador como valor da chave.
  """
  @spec admission(term()) :: {:via, module(), term()}
  def admission(instance), do: Admission.name(instance)

  @doc "O nome registrado do transactor de uma instância."
  @spec transactor(term()) :: {:via, module(), term()}
  def transactor(instance), do: via(:transactor, instance)

  @doc """
  A especificação do transactor, que `Enoch.Instance.Boot` inicia no passo 3.
  """
  @spec transactor_spec(term(), keyword()) :: Supervisor.child_spec() | {module(), keyword()}
  def transactor_spec(instance, opts) do
    {Enoch.Transactor,
     name: transactor(instance),
     owner: owner(instance),
     adapter: Keyword.fetch!(opts, :adapter),
     instance: instance}
  end

  @doc """
  A instância, exigindo que a árvore dela esteja no ar.

  É a guarda do caminho público (`Enoch.transact/2` e `Enoch.db/1`): uma instância
  desconhecida falha de um jeito só, com `ArgumentError` nomeando o nome recebido —
  e não com um `exit(:noproc)` de uma chamada a um nome não registrado (R15).
  """
  @spec fetch!(term()) :: term()
  def fetch!(instance) do
    case Registry.lookup(@registry, {:supervisor, instance}) do
      # A árvore registrada: o pid tem de estar vivo. A limpeza da chave do
      # `Registry` depois de uma queda é assíncrona, e uma chave obsoleta não pode
      # fazer a chamada terminar num `GenServer.call` a um nome morto (R15).
      [{pid, _value}] when is_pid(pid) ->
        if Process.alive?(pid), do: instance, else: not_running!(instance)

      _ ->
        not_running!(instance)
    end
  end

  defp not_running!(instance) do
    raise ArgumentError,
          "instance #{inspect(instance)} is not running: start it with Enoch.start_link/1"
  end

  @impl true
  def init(opts) do
    instance = Keyword.fetch!(opts, :name)
    adapter = Keyword.fetch!(opts, :adapter)
    storage_opts = Keyword.get(opts, :storage_opts, [])
    admission_opts = Keyword.get(opts, :admission, [])

    children = [
      {Enoch.Instance.Owner, name: owner(instance), adapter: adapter, storage_opts: storage_opts},
      {Enoch.Instance.Admission,
       name: admission(instance), instance: instance, opts: admission_opts}
    ]

    Supervisor.init(children,
      strategy: :rest_for_one,
      auto_shutdown: :any_significant
    )
  end

  defp via(role, instance), do: {:via, Registry, {@registry, {role, instance}}}
end
