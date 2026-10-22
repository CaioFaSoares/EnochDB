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

  Os quatro slots do `:atomics`:

  1. o contador de admissão: as transações admitidas e ainda não terminadas;
  2. o limite de admissão;
  3. o estado, fechado ou aberto;
  4. a transação em curso: vale `1` entre o começo do `handle_call` do transactor e o
     `release/1`, e `0` fora dele.

  O slot 4 é o que conta a transação que já saiu da caixa e ainda não foi liberada.
  Sem ele, a reconciliação veria só o `message_queue_len` e subestimaria as transações
  admitidas, e a admissão admitiria acima do limite — a corrida da issue #11. O
  transactor o marca em `mark_in_flight/1` e o desmarca em `clear_in_flight/1`, antes
  de `release/1`.

  Quem chama lê a referência uma vez, com `ref/1`, e opera o contador no próprio
  processo (`admit/2` e `release/1`). O `ref/1` sai do valor registrado no
  `Enoch.InstanceRegistry`, sem passar por mensagem — é o que mantém o caminho da
  escrita sem um processo a mais. As mudanças de estado (`open/1` e `close/1`) são
  chamadas ao processo da admissão, o único que escreve nesse slot.

  A admissão **nasce fechada**: o `init` a põe fechada qualquer que seja o estado
  configurado (D34, R31). Fechada, ela aceita só o caminho interno da subida — `admit/2`
  com `:internal`, usado por `Enoch.Transactor.transact/3` — e nenhuma escrita externa
  passa entre a subida da árvore e o passo 7, que abre a admissão quando a instância
  sobe para ficar aberta. A opção `:status` é o estado desejado ao fim da subida, não o
  estado inicial; uma falha na subida a deixa fechada.

  A caller that dies between incrementing and sending leaves a unit stuck in the
  counter. `reconcile/1` reads the transactor's real mailbox size (`message_queue_len`)
  plus the transaction in progress (`in_flight/1`) and sets the counter to that sum:
  the approximate check D27 chose for this case. The write path
  (`Enoch.Transactor.transact/3`) does not call it. On `{:error, :admission_full}` it
  calls `repair_leak/1`, which rewrites the counter only when the transactor has no
  transaction in progress and an empty mailbox (the signature of a leaked unit), and
  only if no other caller changed the counter since it was read; then it tries to
  admit once more.

  ## The overshoot window

  The limit stays approximate, as R13 and ADR-0004:33 accept: a caller admitted that
  **has not sent yet** shows up neither in `message_queue_len` nor in the in-flight
  slot. While the transactor is busy or has messages waiting, `repair_leak/1` does
  nothing and the limit is exact. The overshoot happens only when every admitted unit
  is still between incrementing and sending, the transactor is idle with an empty
  mailbox, and a rejected caller repairs in that instant: the mailbox can then exceed
  the limit by at most the callers in that window. An exact limit that also repairs a
  dead caller's unit (a monitor per admission) is a work item.

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

  # Os quatro slots do `:atomics`.
  @admitted 1
  @limit 2
  @status 3
  @in_flight 4

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
  admissão: `:limit`, um inteiro positivo, e `:status`, `:open` ou `:closed`). A
  admissão nasce **fechada**; `:status` é o estado que o passo 7 da subida aplica
  (D34, R31). Um valor inválido impede a subida da instância, com erro explícito.
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
              "instance #{inspect(instance)} has no admission counter: the admission " <>
                "starts with the instance tree (Enoch.Instance.Supervisor)"
    end
  end

  @doc """
  Incrementa o contador em nome de quem chama e diz se a transação foi admitida.

  Roda no processo de quem chama, antes de a mensagem entrar na caixa do transactor
  (D27). Devolve `:ok`, `{:error, :admission_closed}` com a admissão fechada ou
  `{:error, :admission_full}` acima do limite; no erro de limite o chamador rejeitado
  não consome unidade — o laço de compare-and-set não chega a incrementar —, e nada é
  enviado. O caminho `:internal` da subida incrementa sem consultar estado nem limite:
  a subida escreve sempre (D34).
  """
  @spec admit(ref(), source()) ::
          :ok | {:error, :admission_closed} | {:error, :admission_full}
  def admit(ref, source \\ :external)

  def admit(ref, :external) do
    if :atomics.get(ref, @status) == @closed do
      {:error, :admission_closed}
    else
      admit_within_limit(ref)
    end
  end

  def admit(ref, :internal) do
    :atomics.add_get(ref, @admitted, 1)
    :ok
  end

  # O incremento só acontece se o contador ainda tem vaga (R13, issue #11 R01). Um
  # incremento seguido de desfazimento deixaria o desfazimento correr contra a
  # reconciliação de outro chamador: a reconciliação reescreve o contador com a caixa
  # mais a transação em curso, e o desfazimento atrasado o baixaria abaixo da caixa —
  # a admissão admitiria acima do limite sem ninguém na janela de excesso (os
  # admitidos que ainda não enviaram). O laço de compare-and-set não escreve no
  # caminho de rejeição, e a única escrita que baixa o contador é a liberação de uma
  # transação admitida.
  defp admit_within_limit(ref) do
    limit = :atomics.get(ref, @limit)
    admitted = :atomics.get(ref, @admitted)

    if admitted >= limit do
      {:error, :admission_full}
    else
      case :atomics.compare_exchange(ref, @admitted, admitted, admitted + 1) do
        :ok -> :ok
        _changed -> admit_within_limit(ref)
      end
    end
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
  Zera o contador e a transação em curso: o `init` do transactor chama, porque a caixa
  nova nasce vazia (D27).

  É o que devolve a zero o contador de admissão depois da queda do transactor (R13).
  """
  @spec reset(ref()) :: :ok
  def reset(ref) do
    :atomics.put(ref, @admitted, 0)
    :atomics.put(ref, @in_flight, 0)
  end

  @doc """
  Marca que a transação saiu da caixa e está em curso no transactor (D27).

  O `handle_call` do transactor chama antes de gravar: a transação já não conta na
  caixa da entrada e ainda não foi liberada, e é a soma das duas que não pode passar do
  limite.
  """
  @spec mark_in_flight(ref()) :: :ok
  def mark_in_flight(ref), do: :atomics.put(ref, @in_flight, 1)

  @doc """
  Desmarca a transação em curso: o transactor chama logo antes de `release/1`.

  A ordem importa: desmarcar antes de liberar mantém a soma da caixa com a transação em
  curso menor ou igual ao contador, e a reconciliação nunca a aumenta.
  """
  @spec clear_in_flight(ref()) :: :ok
  def clear_in_flight(ref), do: :atomics.put(ref, @in_flight, 0)

  @doc """
  A transação em curso: `1` enquanto o transactor grava uma, `0` fora disso.

  Só a observação e a reconciliação a leem; quem a escreve é o transactor, com
  `mark_in_flight/1` e `clear_in_flight/1`.
  """
  @spec in_flight(term()) :: 0 | 1
  def in_flight(instance), do: :atomics.get(ref(instance), @in_flight)

  @doc """
  Deixa o contador igual às transações que estão de fato na caixa e em curso.

  É a reconciliação do chamador que morreu entre incrementar e enviar (D27): lê o
  `message_queue_len` do transactor e a transação em curso (`in_flight/1`), e escreve a
  soma no contador. É a checagem aproximada que a D27 escolheu — um chamador admitido
  que ainda não enviou não aparece em nenhuma das duas, e o incremento dele se perde.
  Sem ela, a unidade presa barraria toda escrita nova ao encher o contador, e nenhuma
  transação nova rodaria para corrigi-lo; por isso `Enoch.Transactor.transact/3`
  reconcilia quando a admissão está cheia e tenta de novo uma vez.

  Com o transactor fora do ar a caixa não existe e o contador vai a zero; o `init` do
  novo transactor o zera de qualquer forma.
  """
  @spec reconcile(term()) :: :ok
  def reconcile(instance) do
    ref = ref(instance)
    :atomics.put(ref, @admitted, pending(instance, ref))
  end

  @doc """
  Repairs units leaked by callers that died between incrementing and sending, without
  erasing callers that are about to send.

  It acts only when the transactor has no transaction in progress and nothing in its
  mailbox, and it resets the counter with a compare-and-set against the value it read,
  so an admission that happened in between keeps its unit. `Enoch.Transactor.transact/3`
  calls it on `{:error, :admission_full}`.
  """
  @spec repair_leak(term()) :: :ok
  def repair_leak(instance) do
    ref = ref(instance)
    observed = :atomics.get(ref, @admitted)

    if observed > 0 and pending(instance, ref) == 0 do
      :atomics.compare_exchange(ref, @admitted, observed, 0)
    end

    :ok
  end

  @doc """
  Abre a admissão: é o passo 7 da sequência de subida (D34, R31).
  """
  @spec open(term()) :: :ok
  def open(instance), do: GenServer.call(name(instance), :open)

  @doc """
  Fecha a admissão: o estado inicial da árvore da instância e o de uma subida que falha
  (D34, R31). Só o caminho interno escreve nesse estado.
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
         {:ok, _desired_status} <- status_option(admission_opts) do
      ref = :atomics.new(4, signed: true)
      :atomics.put(ref, @limit, limit)

      # A admissão nasce fechada (D34, R31): o passo 7 da subida a abre quando a
      # instância sobe para ficar aberta. O `:status` configurado é o estado desejado
      # ao fim da subida, não o inicial.
      :atomics.put(ref, @status, @closed)

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

  # O tamanho real da caixa do transactor mais a transação em curso, ou o contador em
  # vigor quando o transactor não responde: uma transação em curso já saiu da caixa e
  # só é decrementada em `release/1`, então o slot `@in_flight` a conta.
  defp pending(instance, ref) do
    case GenServer.whereis(Supervisor.transactor(instance)) do
      transactor when is_pid(transactor) -> inbox(transactor, ref)
      nil -> 0
    end
  end

  defp inbox(transactor, ref) do
    case Process.info(transactor, :message_queue_len) do
      {:message_queue_len, queue_len} -> queue_len + :atomics.get(ref, @in_flight)
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
