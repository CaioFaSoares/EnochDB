defmodule Enoch.Transactor do
  @moduledoc """
  O único escritor da instância: serializa as transações e passa pela admissão
  (D14, D21, D27).

  Um `GenServer` por instância. Cada transação vira uma mensagem e é aplicada por
  inteiro, uma de cada vez, pelo adaptador em `append/2`. Nesta fatia ele aceita só
  as operações cruas de afirmar e retrair — `[:add, e, a, v]` e
  `[:retract, e, a, v]`. Mapas, tempids, lookup refs, `cas` e os metadados de
  transação são da s02 (`Enoch.Tx.Expand` e `Enoch.Tx.Resolve`, R11).

  A escrita passa pela admissão limitada (`Enoch.Instance.Admission`, R13): quem
  chama incrementa o contador de admissão em `:atomics` antes de enviar a mensagem
  e o transactor o decrementa ao terminar. Acima do limite a rejeição volta antes de
  a mensagem entrar na caixa; com a admissão fechada só o caminho interno da subida
  escreve, e é ele que usa a origem `:internal`. Antes de admitir, `transact/3`
  reconcilia o contador com o tamanho real da caixa
  (`Enoch.Instance.Admission.reconcile/1`): é o que desfaz a unidade que um chamador
  morto entre incrementar e enviar deixou presa (D27).

  O estado do adaptador e a referência do contador de admissão são lidos no `init`:
  o primeiro do dono das tabelas (ver `Enoch.Instance.Owner`) e a segunda de
  `Enoch.Instance.Admission.ref/1`, que lê o valor publicado no `Registry`; ali o
  `init` zera o contador, porque a caixa nova nasce vazia. Na árvore da
  instância o dono e a admissão vêm antes no `:rest_for_one`, então a queda de um
  deles reinicia o transactor junto e o `init` relê o estado, sem estado defasado.

  O `call` usa o tempo limite de quinze segundos do `canon/chat.md`. Uma transação
  que estoure o tempo pode ter sido aplicada; a defesa é uma chave de idempotência
  com `unique: :identity` (D27, R13).

  Referências: `docs/arquitetura.md` (`transactor.ex`), ADR-0004 e a spec em
  `docs/_sprints/s01-nucleo-enoch/03_spec/handovers/spec.md` (R11, R13, R30).
  """

  use GenServer

  alias Enoch.Instance.Admission
  alias Enoch.Instance.Owner
  alias Enoch.Instance.Supervisor

  @timeout 15_000

  @typedoc """
  Nome da operação crua.
  """
  @type operation_name :: :add | :retract

  @typedoc """
  Operação crua da transação: `[:add, e, a, v]` ou `[:retract, e, a, v]`.

  Elixir não tem tipo de lista de tamanho fixo: o tipo diz que a lista começa com
  o nome da operação, e a forma exata dos quatro elementos é conferida na chamada.
  """
  @type operation :: [operation_name() | term()]

  @doc """
  Sobe o transactor da instância.

  Opções: `:name` (obrigatória, o nome registrado), `:owner` (obrigatória, o nome
  registrado do dono das tabelas), `:adapter` (obrigatória) e `:instance`
  (obrigatória, o nome da instância, por onde o `init` lê o contador de admissão).
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))
  end

  @doc """
  Aplica uma transação crua a uma instância: as operações viram os datoms de uma
  única escrita.

  Roda no processo de quem chama e é o único caminho de escrita: reconcilia o
  contador de admissão e depois passa pela admissão antes de enviar a mensagem ao
  transactor (R13), e o `transactor` da instância é resolvido por
  `Enoch.Instance.Supervisor.transactor/1`. Devolve o `t` da transação gravada, ou o
  erro explícito da admissão (`:admission_full` acima do limite e
  `:admission_closed` com a admissão fechada), da operação inválida ou do adaptador;
  a transação inteira é recusada, sem gravar nada.

  A reconciliação vem antes do incremento porque um contador preso — a unidade que um
  chamador morto entre incrementar e enviar vazou (D27) — barraria esta escrita e
  nenhuma transação nova rodaria para corrigi-lo.

  A origem `:internal` é o caminho interno da subida, que incrementa a admissão e
  escreve mesmo com ela fechada (D34, R31).
  """
  @spec transact(term(), [operation()], Admission.source()) ::
          {:ok, Enoch.Storage.tx()} | {:error, term()}
  def transact(instance, operations, source \\ :external) do
    Admission.reconcile(instance)

    with :ok <- Admission.admit(Admission.ref(instance), source) do
      GenServer.call(Supervisor.transactor(instance), {:transact, operations}, @timeout)
    end
  end

  @impl true
  def init(opts) do
    adapter = Keyword.fetch!(opts, :adapter)
    storage = Owner.storage(Keyword.fetch!(opts, :owner))
    admission = Admission.ref(Keyword.fetch!(opts, :instance))

    # A caixa nova nasce vazia: o `init` do transactor zera o contador de admissão
    # (D27, R13).
    Admission.reset(admission)

    {:ok, %{adapter: adapter, storage: storage, admission: admission}}
  end

  @impl true
  def handle_call({:transact, operations}, _from, state) do
    reply =
      with {:ok, datoms} <- datoms(operations) do
        state.adapter.append(state.storage, datoms)
      end

    # Uma transação admitida termina aqui, gravada ou recusada (D27).
    Admission.release(state.admission)

    {:reply, reply, state}
  end

  # As operações cruas viram os datoms do adaptador (D16): afirmar é `added = true`
  # e retrair é `added = false`. Uma operação fora da forma esperada interrompe a
  # tradução e a transação inteira é recusada, sem gravar nada.
  defp datoms(operations) when is_list(operations), do: datoms(operations, [])
  defp datoms(other), do: {:error, {:invalid_operations, other}}

  defp datoms([], acc), do: {:ok, Enum.reverse(acc)}
  defp datoms([[:add, e, a, v] | rest], acc), do: datoms(rest, [{e, a, v, true} | acc])
  defp datoms([[:retract, e, a, v] | rest], acc), do: datoms(rest, [{e, a, v, false} | acc])
  defp datoms([operation | _rest], _acc), do: {:error, {:invalid_operation, operation}}
end
