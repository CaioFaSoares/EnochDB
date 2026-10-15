defmodule Enoch.Instance.Admission do
  @moduledoc """
  A admissão limitada da instância: o contador em `:atomics` e os estados fechado e
  aberto (D27, D34, R13).

  O BEAM não tem caixa de entrada limitada, então a admissão é explícita: quem chama
  incrementa o contador antes de enviar a transação e o transactor o decrementa ao
  terminar (D27). Acima do limite a rejeição volta antes de a mensagem entrar na caixa
  do transactor — filtrar dentro do transactor seria pior, porque a mensagem já teria
  ocupado a caixa; não existe um `GenServer` com `max_queue`.

  O contador mora num processo próprio da árvore da instância (ver
  `Enoch.Instance.Supervisor`) e não no transactor: a queda do transactor reinicia só
  ele, e o `init` do novo zera o contador, porque a caixa nova nasce vazia (D27). A
  mesma referência `:atomics` continua valendo para quem já a tinha.

  Os três slots do `:atomics`:

  1. o contador de admissão: as transações admitidas e ainda não terminadas;
  2. o limite de admissão;
  3. o estado, fechado ou aberto.

  Quem chama lê a referência uma vez, com `ref/1`, e opera o contador no próprio
  processo (`admit/2` e `release/1`). O `ref/1` sai do valor registrado no
  `Enoch.InstanceRegistry`, sem passar por mensagem — é o que mantém o caminho da
  escrita sem um processo a mais. As mudanças de estado (`open/1` e `close/1`) são
  chamadas ao processo da admissão, o único que escreve nesse slot.

  Fechada, a admissão aceita só o caminho interno da subida: `admit/2` com `:internal`,
  usado por `Enoch.Transactor.transact/3`. É o passo 3 da sequência de subida, e o passo
  7 a abre (D34, R31); uma falha na subida a deixa fechada.

  Um chamador que morre entre incrementar e enviar deixa uma unidade presa no contador.
  A reconciliação de `reconcile/1` lê o tamanho real da caixa do transactor
  (`message_queue_len`) e deixa o contador igual a ele: é a checagem aproximada que a
  D27 escolheu para esse caso. Ela vale com o transactor sem transação em andamento,
  porque uma transação em curso já saiu da caixa e ainda não foi decrementada. O
  caminho da escrita (`Enoch.Transactor.transact/3`) reconcilia antes de admitir: sem
  isso, a unidade presa barraria toda escrita nova ao encher o contador, e nenhuma
  transação nova rodaria para corrigi-lo.

  Referências: `docs/arquitetura.md` (`instance/admission.ex`), ADR-0004, ADR-0008 e a
  spec em `docs/_sprints/s01-nucleo-enoch/03_spec/handovers/spec.md` (R13). A telemetria
  do tamanho da fila fica na s05 (D27, R17).
  """

  use GenServer

  alias Enoch.Instance.Supervisor

  @registry Enoch.InstanceRegistry

  # A chave do registro da instância e o papel no nome via: a admissão é o único filho
  # que publica um valor no registro — a própria referência do contador.
  @key :admission

  # Os três slots do `:atomics`.
  @admitted 1
  @limit 2
  @status 3

  # Os dois estados da admissão: fechada aceita só o caminho interno da subida (D34).
  @closed 0
  @open 1

  # Nenhuma decisão fixa o limite; o número é do agente e a subida pode mudá-lo pela
  # opção `admission:` do `Enoch.start_link/1`.
  @default_limit 32

  @typedoc """
  O contador de admissão: quem chama incrementa por ele antes de enviar a transação.
  """
  @type ref :: :atomics.atomics_ref()

  @typedoc """
  A origem da transação.

  `:external` passa pela admissão — estado e limite valem; `:internal` é o caminho
  interno da subida, que escreve com a admissão fechada (D34).
  """
  @type source :: :external | :internal

  @typedoc "O estado da admissão."
  @type status :: :open | :closed

  @doc """
  Sobe a admissão da instância.

  Opções: `:name` (obrigatória, o nome registrado, ver `name/1`), `:instance`
  (obrigatória, o nome da instância — a chave do registro) e `:opts` (as opções da
  admissão: `:limit`, um inteiro positivo, e `:status`, `:open` ou `:closed`). Um valor
  inválido impede a subida da instância, com erro explícito.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))
  end

  @doc """
  O nome registrado da admissão de uma instância.

  O processo da admissão é o dono do contador: registra-se com este nome e publica a
  referência do `:atomics` como valor da mesma chave do `Enoch.InstanceRegistry`. O
  `Enoch.Instance.Supervisor.admission/1` devolve o mesmo nome.
  """
  @spec name(term()) :: {:via, module(), term()}
  def name(instance), do: {:via, Registry, {@registry, key(instance)}}

  @doc """
  O contador de admissão da instância.

  Sai do valor registrado, sem passar por mensagem, para o caminho da escrita
  incrementá-lo no processo de quem chama (D27). Exige a instância no ar.
  """
  @spec ref(term()) :: ref()
  def ref(instance) do
    case Registry.lookup(@registry, key(instance)) do
      [{_admission, ref}] ->
        ref

      [] ->
        raise ArgumentError,
              "a instância #{inspect(instance)} não tem admissão: o contador de " <>
                "admissão nasce com a árvore da instância (Enoch.Instance.Supervisor)"
    end
  end

  @doc """
  Incrementa o contador em nome de quem chama e diz se a transação foi admitida.

  Roda no processo de quem chama, antes de a mensagem entrar na caixa do transactor
  (D27). Devolve `:ok`, `{:error, :admission_closed}` com a admissão fechada ou
  `{:error, :admission_full}` acima do limite; no erro de limite o incremento do
  chamador rejeitado é desfeito, e nada é enviado. O caminho `:internal` da subida
  incrementa sem consultar estado nem limite: a subida escreve sempre (D34).
  """
  @spec admit(ref(), source()) ::
          :ok | {:error, :admission_closed} | {:error, :admission_full}
  def admit(ref, source \\ :external)

  def admit(ref, :external) do
    if :atomics.get(ref, @status) == @closed do
      {:error, :admission_closed}
    else
      admitted = :atomics.add_get(ref, @admitted, 1)

      if admitted > :atomics.get(ref, @limit) do
        # O chamador rejeitado desfaz o próprio incremento (R13).
        :atomics.sub(ref, @admitted, 1)
        {:error, :admission_full}
      else
        :ok
      end
    end
  end

  def admit(ref, :internal) do
    :atomics.add_get(ref, @admitted, 1)
    :ok
  end

  @doc """
  Desfaz um incremento admitido: o transactor chama ao terminar a transação.

  Um decremento nunca deixa o contador negativo. A reconciliação pode tê-lo baixado
  enquanto um chamador tinha o incremento feito, e um contador negativo admitiria acima
  do limite.
  """
  @spec release(ref()) :: :ok
  def release(ref) do
    if :atomics.sub_get(ref, @admitted, 1) < 0, do: :atomics.put(ref, @admitted, 0)

    :ok
  end

  @doc """
  Zera o contador: o `init` do transactor chama, porque a caixa nova nasce vazia (D27).

  É o que devolve a zero o contador de admissão depois da queda do transactor (R13).
  """
  @spec reset(ref()) :: :ok
  def reset(ref), do: :atomics.put(ref, @admitted, 0)

  @doc """
  Deixa o contador igual às transações que estão de fato na caixa do transactor.

  É a reconciliação do chamador que morreu entre incrementar e enviar (D27): lê o
  `message_queue_len` do transactor e escreve o mesmo número no contador. A leitura é
  a checagem aproximada que a D27 escolheu — um chamador admitido que ainda não enviou
  não aparece na caixa, e o incremento dele se perde. Sem ela, a unidade presa barraria
  toda escrita nova ao encher o contador, e nenhuma transação nova rodaria para
  corrigi-lo; por isso `Enoch.Transactor.transact/3` reconcilia antes de admitir.

  Vale com o transactor sem transação em andamento: uma transação em curso já saiu da
  caixa e o transactor só a decrementa ao terminar, então escrever o tamanho da caixa
  no contador por baixo dela admitiria acima do limite. Com o transactor fora do ar a
  caixa não existe e o contador vai a zero; o `init` do novo transactor o zera de
  qualquer forma.
  """
  @spec reconcile(term()) :: :ok
  def reconcile(instance) do
    ref = ref(instance)
    :atomics.put(ref, @admitted, pending(instance, ref))
  end

  @doc """
  Abre a admissão: é o passo 7 da sequência de subida (D34, R31).
  """
  @spec open(term()) :: :ok
  def open(instance), do: GenServer.call(name(instance), :open)

  @doc """
  Fecha a admissão: é o passo 3 da sequência de subida, e a falha de um passo a deixa
  fechada (D34, R31). Só o caminho interno escreve nesse estado.
  """
  @spec close(term()) :: :ok
  def close(instance), do: GenServer.call(name(instance), :close)

  @doc "O estado da admissão: `:open` ou `:closed`."
  @spec status(term()) :: status()
  def status(instance) do
    case :atomics.get(ref(instance), @status) do
      @open -> :open
      @closed -> :closed
    end
  end

  @doc "O limite de admissão em vigor."
  @spec limit(term()) :: pos_integer()
  def limit(instance), do: :atomics.get(ref(instance), @limit)

  @doc """
  O contador de admissão: as transações admitidas e ainda não terminadas.

  A telemetria do tamanho da fila é da s05 (D27); aqui ele é a leitura que os testes da
  admissão e a subida usam.
  """
  @spec counter(term()) :: integer()
  def counter(instance), do: :atomics.get(ref(instance), @admitted)

  @impl true
  def init(opts) do
    instance = Keyword.fetch!(opts, :instance)
    admission_opts = Keyword.get(opts, :opts, [])

    with {:ok, limit} <- limit_option(admission_opts),
         {:ok, status} <- status_option(admission_opts) do
      ref = :atomics.new(3, signed: true)
      :atomics.put(ref, @limit, limit)
      :atomics.put(ref, @status, status)

      # A referência é publicada como valor do registro para quem chama lê-la sem
      # passar por mensagem (D27).
      Registry.update_value(@registry, key(instance), fn _ref -> ref end)

      {:ok, %{ref: ref}}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call(:open, _from, state) do
    :atomics.put(state.ref, @status, @open)
    {:reply, :ok, state}
  end

  def handle_call(:close, _from, state) do
    :atomics.put(state.ref, @status, @closed)
    {:reply, :ok, state}
  end

  defp key(instance), do: {@key, instance}

  # O tamanho real da caixa do transactor, ou o contador em vigor quando ele está no
  # meio de uma transação: `:running` é o transactor executando, e nesse estado a caixa
  # não conta a transação em curso, que só é decrementada ao terminar. Fora isso
  # (`:waiting` parado no `receive`, `:suspended`) não há transação em andamento e a
  # caixa é a fonte.
  defp pending(instance, ref) do
    case GenServer.whereis(Supervisor.transactor(instance)) do
      transactor when is_pid(transactor) -> inbox(transactor, ref)
      nil -> 0
    end
  end

  defp inbox(transactor, ref) do
    case Process.info(transactor, [:message_queue_len, :status]) do
      [message_queue_len: _queue_len, status: :running] -> :atomics.get(ref, @admitted)
      [message_queue_len: queue_len, status: _status] -> queue_len
      nil -> :atomics.get(ref, @admitted)
    end
  end

  defp limit_option(opts) do
    case Keyword.get(opts, :limit, @default_limit) do
      limit when is_integer(limit) and limit > 0 -> {:ok, limit}
      other -> {:error, {:invalid_admission_limit, other}}
    end
  end

  defp status_option(opts) do
    case Keyword.get(opts, :status, :open) do
      :open -> {:ok, @open}
      :closed -> {:ok, @closed}
      other -> {:error, {:invalid_admission_status, other}}
    end
  end
end
