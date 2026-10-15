defmodule Enoch do
  @moduledoc """
  Ponto de entrada do pacote `enoch`: a API pública por nome de instância.

  Uma instância é um banco com nome próprio, criado em tempo de execução (D32,
  ADR-0007). `start_link/1` sobe a árvore de supervisão da instância — o dono das
  tabelas e o transactor, ver `Enoch.Instance.Supervisor` — e as chamadas
  seguintes recebem o nome:

      {:ok, _} =
        Enoch.start_link(
          name: MyApp.Db,
          adapter: Enoch.Adapters.Memory,
          storage_opts: [max_memory: :infinity]
        )

      {:ok, 1} = Enoch.transact(MyApp.Db, [[:add, 100, 10, 7]])
      Enoch.DB.basis_t(Enoch.db(MyApp.Db))

  Nesta fatia a API traz `start_link/1`, `transact/2` (só as operações cruas de
  afirmar e retrair, R11) e `db/1`; `use Enoch.Repo` e o restante da API do e01 —
  `q`, `pull`, `as_of` e `history` — entram nas fatias seguintes.

  `start_link/1` executa a sequência de subida em sete passos (D34, R31) e recebe
  as listas de módulos da instância: `schema:`, `functions:` e `rules:` (D35). O
  registro genérico dessas listas, com a recusa de dois módulos que registrem o
  mesmo nome, mora em `Enoch.Instance.Boot` nesta sprint.

  O nome da instância pode ser qualquer termo; o módulo de um `use Enoch.Repo` é o
  uso típico. O `adapter:` é o módulo que implementa `Enoch.Storage`, e as
  `storage_opts:` vão para o `adapter.open/1` do dono das tabelas.

  A árvore de pastas está em `docs/arquitetura.md`, o vocabulário em `CONTEXT.md`,
  as decisões em `docs/adr/` e os requisitos (R11, R13, R24, R30, R31) na spec em
  `docs/_sprints/s01-nucleo-enoch/03_spec/handovers/spec.md`.
  """

  @doc """
  Sobe a árvore de supervisão de uma instância e executa a subida.

  Opções: `:name` (obrigatória, o nome da instância), `:adapter` (obrigatória),
  `:storage_opts` (as opções de `adapter.open/1`; no `Memory` o `max_memory` é
  obrigatório, D20), `:admission` (as opções da admissão limitada: `:limit`, o
  número de transações admitidas e ainda não terminadas que a instância aceita, com
  padrão 32, e `:status`, `:open` por padrão ou `:closed`, ver
  `Enoch.Instance.Admission`, D27), `:schema`, `:functions` e `:rules` (as listas de
  módulos da instância, D35). O dono das tabelas abre o storage, a admissão sobe com
  o contador e o transactor sobe atrás dos dois.

  A árvore de pé, `Enoch.Instance.Boot.run/2` executa a sequência de subida em sete
  passos (D34, R31) — a versão do layout, a conferência do estado atual, a admissão
  fechada, o registro das funções e regras, e a abertura da admissão com a
  telemetria da base. Uma falha em qualquer passo impede a subida: a árvore é
  derrubada e `{:error, motivo}` volta com o erro explícito do passo que falhou, com
  a admissão fechada.
  """
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    instance = Keyword.fetch!(opts, :name)

    with {:ok, sup} <- Enoch.Instance.Supervisor.start_link(opts) do
      case Enoch.Instance.Boot.run(instance, opts) do
        {:ok, _registry} ->
          {:ok, sup}

        {:error, reason} ->
          Supervisor.stop(sup, :normal, 5_000)
          {:error, reason}
      end
    end
  end

  @doc """
  Aplica uma transação crua a uma instância e devolve o `t` gravado.

  As operações são `[:add, e, a, v]` e `[:retract, e, a, v]` (R11, só o cru nesta
  sprint). O transactor da instância serializa a escrita e ela é tudo ou nada.

  A escrita passa pela admissão limitada (R13): acima do limite a rejeição explícita
  `{:error, :admission_full}` volta antes de a mensagem entrar na caixa do transactor
  e, com a admissão fechada, uma escrita externa é rejeitada com
  `{:error, :admission_closed}`.
  """
  @spec transact(term(), [Enoch.Transactor.operation()]) ::
          {:ok, Enoch.Storage.tx()} | {:error, term()}
  def transact(name, operations), do: Enoch.Transactor.transact(name, operations)

  @doc """
  O banco como valor da instância, na base publicada (D16, D18).

  O valor é imutável e custa O(1): guarda as referências das tabelas e o `basis_t`,
  que se lê com `Enoch.DB.basis_t/1`.
  """
  @spec db(term()) :: Enoch.DB.t()
  def db(name) do
    Enoch.Instance.Owner.db(Enoch.Instance.Supervisor.owner(name))
  end
end
