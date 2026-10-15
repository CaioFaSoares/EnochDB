defmodule Enoch.Instance.Supervisor do
  @moduledoc """
  Árvore de supervisão de uma instância do banco (D32, D21, D27).

  Cada instância — o nome que o chamador dá em `Enoch.start_link/1` — sobe a
  própria árvore, e duas instâncias com nomes diferentes convivem no mesmo nó sem
  compartilhar estado: cada uma abre as próprias tabelas no processo dono
  (`Enoch.Instance.Owner`), tem a própria admissão
  (`Enoch.Instance.Admission`) e o próprio transactor (`Enoch.Transactor`).

  A estratégia é `:rest_for_one`, na ordem dono, admissão e transactor. A queda do
  transactor reinicia só ele: o dono segue vivo com as tabelas e a admissão segue
  com o contador, cujo `init` novo zera (D27) — a recuperação da ADR-0003 depende
  disso. A queda do dono ou da admissão reinicia o transactor junto, que relê o
  estado do adaptador no `init` e nunca fica defasado.

  Os três filhos são registrados no `Registry` global da aplicação
  (`Enoch.InstanceRegistry`, ver `Enoch.Application`), com o nome da instância na
  chave. `owner/1`, `admission/1` e `transactor/1` devolvem esses nomes e `name/1`
  devolve o da própria árvore. O nome da instância pode ser qualquer termo; o
  módulo de um `use Enoch.Repo` é o uso típico (ADR-0007).

  Referências: `docs/arquitetura.md` (`instance/supervisor.ex`), ADR-0003,
  ADR-0004, ADR-0007, ADR-0008 e a spec em
  `docs/_sprints/s01-nucleo-enoch/03_spec/handovers/spec.md` (R13, R30). Esta
  árvore sobe o dono, a admissão e o transactor direto, com a admissão no estado
  da opção `:status` (padrão aberta); a sequência de subida em sete passos
  (`boot.ex`, D34) é executada por `Enoch.start_link/1` depois da árvore de pé, e é
  ela que fecha a admissão nos passos internos e a abre no passo 7.
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

  @impl true
  def init(opts) do
    instance = Keyword.fetch!(opts, :name)
    adapter = Keyword.fetch!(opts, :adapter)
    storage_opts = Keyword.get(opts, :storage_opts, [])
    admission_opts = Keyword.get(opts, :admission, [])

    children = [
      {Enoch.Instance.Owner, name: owner(instance), adapter: adapter, storage_opts: storage_opts},
      {Enoch.Instance.Admission,
       name: admission(instance), instance: instance, opts: admission_opts},
      {Enoch.Transactor,
       name: transactor(instance), owner: owner(instance), adapter: adapter, instance: instance}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end

  defp via(role, instance), do: {:via, Registry, {@registry, {role, instance}}}
end
