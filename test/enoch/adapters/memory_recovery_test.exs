defmodule Enoch.Adapters.MemoryRecoveryTest do
  @moduledoc """
  A recuperação do `Memory` depois da queda do transactor no meio da escrita: as
  linhas órfãs, a reconstrução do estado atual e o contador que nunca volta (R5,
  D18, ADR-0003).

  A suíte tem dois níveis. O de ponta a ponta mata o transactor de verdade no meio
  da escrita da transação `t+1` — depois de o histórico dela estar inteiro e de o
  rascunho dela já estar no estado atual — com um leitor varrendo durante a
  recuperação, e confere o `t+2` da transação seguinte e a sobrevivência das
  tabelas. O do adaptador monta a escrita pela metade pelas fases públicas
  (`begin_tx`, `write_history`, `apply_current`, como a suíte do leitor) e chama
  `recover/1` direto, onde o desfecho é determinístico.

  A janela entre a queda e o fim da recuperação é alargada com `:sys.suspend` no
  dono: a recuperação roda na entrega do storage ao transactor novo (ver
  `Enoch.Instance.Owner`), e o dono suspenso segura essa entrega, deixando o estado
  intermediário — contador em `2t+1` e órfãs no histórico — observável. A janela
  existe em produção; o teste só não depende de ganhar a corrida contra ela.

  Referências: `docs/_sprints/s01-nucleo-enoch/03_spec/handovers/spec.md` (R5),
  `docs/adr/0003-*.md` e a issue #7.
  """

  use ExUnit.Case, async: false

  alias Enoch.Adapters.Memory
  alias Enoch.DB
  alias Enoch.Instance.Admission
  alias Enoch.Instance.Owner
  alias Enoch.Instance.Supervisor, as: Instance

  @aberto [max_memory: :infinity]
  @espera 10_000

  # O atributo 10 é o da base; o 20 só aparece na transação que cai, e as entidades
  # dela começam em 100 001, longe das entidades 1..t da base.
  @attr_base 10
  @attr_em_voo 20
  @base_em_voo 100_000
  @linhas_base 2_000
  @linhas_em_voo 100_000

  describe "queda do transactor no meio da escrita (R5, D18)" do
    test "a recuperação apaga as órfãs, reconstrói o presente e a seguinte é t+2" do
      cenario = Enum.find_value(1..3, fn _tentativa -> montar_queda() end)
      assert cenario, "a escrita não caiu no meio em três tentativas"

      %{nome: nome, sup: sup, owner: owner, storage: storage, t: t} = cenario
      %{refs: {history, current, counter}} = storage

      # A queda: o contador preso em `2t+1`, as órfãs da `t+1` no histórico e o
      # rascunho dela no estado atual — inclusive a retração da entidade 1, que só
      # a transação que caiu fez. O `t` ainda não foi reutilizado: nada foi
      # publicado.
      assert 2 * t + 1 == :atomics.get(counter, 1)
      assert @linhas_em_voo + 1 == conta_tx(history, t + 1)
      assert 0 < contagem_no_presente(current, @attr_em_voo)
      assert contagem_no_presente(current, @attr_em_voo) < @linhas_em_voo
      refute :ets.member(current, {1, @attr_base, 1})

      # O incremento de admissão do chamador que morreu no meio não foi desfeito: o
      # `init` do transactor novo é quem zera o contador de admissão (R5).
      assert 1 == Admission.counter(nome)

      # O leitor em curso: um banco como valor da base `t`, capturado com o contador
      # preso na queda. A primeira varredura dele é da janela da queda, antes de a
      # recuperação começar.
      esperado = Enum.sort(for e <- 1..t, do: {e, @attr_base, e})
      pai = self()
      leitor = spawn(fn -> ler_sem_parar(pai, storage, esperado) end)
      primeira = receber_leitura()
      assert t == primeira.base
      assert 2 * t + 1 == primeira.counter
      assert primeira.historico
      assert primeira.fiel

      # Soltar o dono solta a entrega do storage ao transactor novo, e a recuperação
      # roda ali dentro; o leitor segue varrendo enquanto ela roda.
      :sys.resume(owner)

      :ok =
        aguardar(
          fn -> 2 * (t + 1) == :atomics.get(counter, 1) end,
          "a recuperação não publicou 2(t+1)"
        )

      observacoes = [primeira | parar_leitor(leitor)]

      # As órfãs saíram, o estado atual foi reconstruído do histórico até `t` — a
      # retração da entidade 1 voltou e o rascunho da `t+1` sumiu — e o contador
      # está publicado em `2(t+1)`.
      assert 0 == conta_tx(history, t + 1)
      assert 2 * (t + 1) == :atomics.get(counter, 1)
      assert t == :ets.info(history, :size)
      assert 0 == contagem_no_presente(current, @attr_em_voo)
      assert :ets.member(current, {1, @attr_base, 1})

      db = Memory.db(storage)
      assert t + 1 == DB.basis_t(db)

      assert Enum.sort(Memory.scan_aevt(db, a: @attr_base)) ==
               Enum.sort(for e <- 1..t, do: {e, @attr_base, e, nil, nil})

      assert Memory.scan_aevt(db, a: @attr_em_voo) == []

      # Toda varredura do leitor casou com a base `t`, veio do histórico — o estado
      # atual com a base passada é justamente o que a guarda do contador proíbe — e
      # o contador que ela viu é o da queda ou o da recuperação.
      assert Enum.all?(observacoes, & &1.fiel),
             "varredura divergente da base durante a recuperação"

      assert Enum.all?(observacoes, & &1.historico),
             "varredura leu o estado atual com a base passada"

      assert Enum.all?(observacoes, &(&1.base == t))

      assert Enum.any?(observacoes, &(&1.counter == 2 * t + 1)),
             "o leitor não viu o contador preso na queda"

      # A transação seguinte é `t+2`: a `t+1` virou uma transação vazia e nenhum `t`
      # é reutilizado.
      assert {:ok, proxima} = Enoch.transact(nome, [[:add, @base_em_voo, @attr_base, 1]])
      assert t + 2 == proxima
      assert t + 2 == DB.basis_t(Enoch.db(nome))
      assert 2 * (t + 2) == :atomics.get(counter, 1)
      assert 0 == conta_tx(history, t + 1)
      assert 0 == Admission.counter(nome)

      # As tabelas sobreviveram à queda do transactor: as mesmas, do mesmo dono, com
      # o heir no supervisor da instância, e o transactor novo está no ar.
      assert :ets.info(history) != :undefined
      assert :ets.info(current) != :undefined
      assert :ets.info(history, :owner) == owner
      assert :ets.info(current, :owner) == owner
      assert :ets.info(history, :heir) == sup
      assert :ets.info(current, :heir) == sup
      assert Process.alive?(GenServer.whereis(Instance.transactor(nome)))
    end
  end

  describe "recover/1 no adaptador (R5, D18)" do
    test "com o contador em 2t+1: as órfãs saem, até t o presente é refeito e o contador vai a 2(t+1)" do
      assert {:ok, %{refs: {history, current, counter}} = storage} = Memory.open(@aberto)

      assert {:ok, 1} =
               Memory.append(storage, [
                 {100, @attr_base, 1, true},
                 {101, @attr_base, 2, true}
               ])

      assert {:ok, 2} = Memory.append(storage, [{102, @attr_base, 3, true}])
      assert 4 == :atomics.get(counter, 1)

      # A transação 3 morre no meio: o histórico dela inteiro, o estado atual só com
      # uma parte — a retração da entidade 102 chegou a valer no rascunho.
      assert 3 == Memory.begin_tx(counter)

      em_voo = [
        {102, @attr_base, 3, false},
        {103, @attr_base, 4, true},
        {200, @attr_em_voo, 9, true}
      ]

      assert :ok = Memory.write_history(history, 3, em_voo)
      assert :ok = Memory.apply_current(current, em_voo)

      assert 5 == :atomics.get(counter, 1)
      assert 3 == conta_tx(history, 3)
      refute :ets.member(current, {102, @attr_base, 3})

      assert :ok = Memory.recover(storage)

      assert 6 == :atomics.get(counter, 1)
      assert 0 == conta_tx(history, 3)
      assert 3 == :ets.info(history, :size)
      assert 0 == contagem_no_presente(current, @attr_em_voo)
      assert :ets.member(current, {102, @attr_base, 3})

      db = Memory.db(storage)
      assert 3 == DB.basis_t(db)

      assert Memory.scan_aevt(db, a: @attr_base) == [
               {100, @attr_base, 1, nil, nil},
               {101, @attr_base, 2, nil, nil},
               {102, @attr_base, 3, nil, nil}
             ]

      assert Memory.scan_aevt(db, a: @attr_em_voo) == []

      # A transação seguinte é `t+2 = 4`: a 3 ficou vazia.
      assert {:ok, 4} = Memory.append(storage, [{300, @attr_base, 5, true}])

      # E sem transação em curso `recover/1` não mexe em nada.
      assert 8 == :atomics.get(counter, 1)
      assert :ok = Memory.recover(storage)
      assert 8 == :atomics.get(counter, 1)
    end

    test "queda antes da primeira linha: o contador avança e a transação seguinte é t+2" do
      assert {:ok, %{refs: {_history, _current, counter}} = storage} = Memory.open(@aberto)

      assert {:ok, 1} = Memory.append(storage, [{100, @attr_base, 1, true}])
      assert 2 == :atomics.get(counter, 1)

      assert 2 == Memory.begin_tx(counter)
      assert 3 == :atomics.get(counter, 1)

      assert :ok = Memory.recover(storage)
      assert 4 == :atomics.get(counter, 1)

      assert {:ok, 3} = Memory.append(storage, [{101, @attr_base, 2, true}])
      assert 6 == :atomics.get(counter, 1)
    end

    test "com o contador par não toca em nada; a reconstrução explícita é que refaz o presente" do
      assert {:ok, %{refs: {history, current, counter}} = storage} = Memory.open(@aberto)
      assert {:ok, 1} = Memory.append(storage, [{100, @attr_base, 1, true}])

      # Um estado atual adulterado, com o contador par: não é a queda no meio da
      # escrita, e `recover/1` não é a conferência do passo 2 da subida (D34);
      # quem refaz o presente é `rebuild_current/2`.
      assert true = :ets.insert(current, {{9, @attr_base, 9}})

      assert :ok = Memory.recover(storage)
      assert 2 == :atomics.get(counter, 1)
      assert 1 == :ets.info(history, :size)
      assert :ets.member(current, {9, @attr_base, 9})

      assert :ok = Memory.rebuild_current(storage, 1)
      refute :ets.member(current, {9, @attr_base, 9})
      assert Memory.scan_eavt(Memory.db(storage), e: 100) == [{100, @attr_base, 1, nil, nil}]
    end
  end

  describe "as tabelas sobrevivem à queda (R5, D18, D21)" do
    test "as tabelas do dono nascem com o heir no supervisor da instância" do
      nome = {__MODULE__, System.unique_integer([:positive])}
      assert {:ok, sup} = Enoch.start_link(name: nome, adapter: Memory, storage_opts: @aberto)
      on_exit(fn -> parar(sup) end)

      %{refs: {history, current, _counter}} = Owner.storage(Instance.owner(nome))

      assert :ets.info(history, :heir) == sup
      assert :ets.info(current, :heir) == sup
      assert :ets.info(history, :owner) == GenServer.whereis(Instance.owner(nome))
    end

    test "com o heir, as tabelas passam para o herdeiro quando o dono cai" do
      pai = self()

      dono =
        spawn(fn ->
          {:ok, storage} = Memory.open(@aberto ++ [heir: pai])
          send(pai, {:storage, storage})

          receive do
            :morra -> :ok
          end
        end)

      assert_receive {:storage, %{refs: {history, current, _counter}} = storage}, 5_000
      assert {:ok, 1} = Memory.append(storage, [{100, @attr_base, 1, true}])
      assert :ets.info(history, :owner) == dono

      Process.exit(dono, :kill)

      # O ETS entrega as tabelas ao heir: elas sobrevivem à morte de quem as abriu.
      assert :ok =
               aguardar(
                 fn -> :ets.info(history, :owner) == pai end,
                 "as tabelas não passaram para o heir"
               )

      assert :ets.info(current, :owner) == pai

      assert Memory.scan_aevt(Memory.db(storage), a: @attr_base) == [
               {100, @attr_base, 1, nil, nil}
             ]

      # As tabelas passaram a ser do processo do teste; a limpeza é dele.
      assert true = :ets.delete(history)
      assert true = :ets.delete(current)
    end
  end

  # --- o cenário da queda ------------------------------------------------------

  # Monta o cenário da queda numa instância de verdade: a base em `t`, o dono
  # suspenso e o transactor morto no meio da escrita da `t+1` — depois de o
  # histórico dela estar inteiro (a última linha) e de o rascunho dela já estar no
  # estado atual (a primeira linha do atributo em voo), que é a fase em que a
  # reconstrução tem o que desfazer. Devolve o cenário, ou `nil` quando a escrita
  # terminou antes do `kill` e a tentativa não serve.
  defp montar_queda do
    nome = {__MODULE__, System.unique_integer([:positive])}
    assert {:ok, sup} = Enoch.start_link(name: nome, adapter: Memory, storage_opts: @aberto)
    on_exit(fn -> parar(sup) end)

    t = @linhas_base
    for e <- 1..t, do: {:ok, ^e} = Enoch.transact(nome, [[:add, e, @attr_base, e]])

    %{refs: {history, current, counter}} = storage = Owner.storage(Instance.owner(nome))
    owner = GenServer.whereis(Instance.owner(nome))
    transactor = GenServer.whereis(Instance.transactor(nome))

    # A recuperação espera na entrega do storage ao transactor novo; o dono suspenso
    # segura essa entrega até o teste soltar.
    :sys.suspend(owner)

    # A transação `t+1` da queda: a retração de uma linha da base primeiro, para a
    # reconstrução ter o que trazer de volta, e uma escrita grande depois, para a
    # queda cair no meio dela.
    em_voo =
      [[:retract, 1, @attr_base, 1]] ++
        for k <- 1..@linhas_em_voo, do: [:add, @base_em_voo + k, @attr_em_voo, k]

    _escritor = spawn(fn -> Enoch.transact(nome, em_voo) end)

    tx = t + 1
    ultima = {@base_em_voo + @linhas_em_voo, @attr_em_voo, @linhas_em_voo, tx}
    primeira = {@base_em_voo + 1, @attr_em_voo, 1}

    # A chave do histórico é `{e, a, v, tx}`, e a do estado atual é `{e, a, v}`.
    :ok =
      aguardar(
        fn -> :ets.member(history, ultima) end,
        "o histórico da transação em voo não foi escrito"
      )

    :ok =
      aguardar(
        fn -> :ets.member(current, primeira) end,
        "o rascunho da transação em voo não chegou ao estado atual"
      )

    ref = Process.monitor(transactor)
    Process.exit(transactor, :kill)
    assert_receive {:DOWN, ^ref, :process, ^transactor, :killed}, 5_000

    if :atomics.get(counter, 1) == 2 * tx - 1 do
      %{
        nome: nome,
        sup: sup,
        owner: owner,
        storage: storage,
        t: t,
        history: history,
        current: current,
        counter: counter
      }
    else
      # A escrita terminou antes do kill: a tentativa não deixou transação no meio.
      parar(sup)
      nil
    end
  end

  # --- o leitor em curso -------------------------------------------------------

  # O leitor: um banco como valor da base da queda — o contador preso em `2t+1` faz
  # `div(contador, 2)` publicar `t` —, varrido sem parar enquanto a recuperação
  # roda. Cada varredura inteira vai para quem chamou: a base, o contador antes e
  # depois, se ela saiu do histórico e se casou com o estado esperado da base.
  defp ler_sem_parar(pai, storage, esperado) do
    db = Memory.db(storage)
    base = DB.basis_t(db)
    %{refs: {_history, _current, counter}} = storage

    varredura = fn ->
      antes = :atomics.get(counter, 1)
      rows = Memory.scan_aevt(db, a: @attr_base)
      depois = :atomics.get(counter, 1)

      fiel =
        Enum.all?(rows, fn {_e, _a, _v, tx, _added} -> is_nil(tx) or tx <= base end) and
          vivo(rows) == esperado

      leitura = %{
        base: base,
        counter: antes,
        depois: depois,
        historico: historico?(rows),
        fiel: fiel
      }

      send(pai, {:leitura, leitura})
    end

    varre_sem_parar(varredura)
  end

  defp varre_sem_parar(varredura) do
    varredura.()

    receive do
      :pare -> :ok
    after
      0 -> varre_sem_parar(varredura)
    end
  end

  defp receber_leitura do
    assert_receive {:leitura, leitura}, 5_000
    leitura
  end

  # Para o leitor e devolve as varreduras que ele mandou: o `:pare` chega depois das
  # varreduras que ele já fez, e o `:DOWN` fecha a conta.
  defp parar_leitor(leitor) do
    ref = Process.monitor(leitor)
    send(leitor, :pare)
    assert_receive {:DOWN, ^ref, :process, ^leitor, :normal}, 5_000
    leituras([])
  end

  defp leituras(acc) do
    receive do
      {:leitura, leitura} -> leituras([leitura | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  # --- auxiliares --------------------------------------------------------------

  # O estado vivo na base, a partir das linhas que a varredura devolveu: no presente
  # as linhas já são os datoms vivos; no histórico vale o último operador por
  # `(e, a, v)` com `tx <= base`. É o mesmo modelo de referência da suíte do leitor e
  # da suíte de contrato; a visibilidade do produto é do avaliador (D8).
  defp vivo(rows) do
    if Enum.all?(rows, fn {_e, _a, _v, tx, _added} -> is_nil(tx) end) do
      rows
      |> Enum.map(fn {e, a, v, _tx, _added} -> {e, a, v} end)
      |> Enum.sort()
    else
      rows
      |> Enum.reduce(%{}, fn {e, a, v, tx, added}, acc ->
        datom = {e, a, v}

        case acc do
          %{^datom => {seen_tx, _seen_added}} when seen_tx >= tx -> acc
          _ -> Map.put(acc, datom, {tx, added})
        end
      end)
      |> Enum.filter(fn {_datom, {_tx, added}} -> added end)
      |> Enum.map(fn {datom, _ultimo} -> datom end)
      |> Enum.sort()
    end
  end

  # As linhas da varredura do histórico trazem o `tx`; as do estado atual, não.
  defp historico?(rows), do: Enum.any?(rows, fn {_e, _a, _v, tx, _added} -> not is_nil(tx) end)

  # As linhas de uma transação no histórico: as órfãs da que caiu e a conta depois
  # da limpeza.
  defp conta_tx(history, tx),
    do: :ets.select_count(history, [{{{:"$1", :"$2", :"$3", tx}, :_}, [], [true]}])

  # As linhas de um atributo no estado atual. O objeto da tabela é o datom
  # embrulhado numa tupla de um elemento, porque a chave é `{e, a, v}`.
  defp contagem_no_presente(current, a) do
    :ets.select_count(current, [{{{:"$1", a, :"$2"}}, [], [true]}])
  end

  # A espera das fases da escrita e do fim da recuperação: a condição é barata — um
  # `:ets.member/2`, uma leitura do contador — e o laço cede a vez a cada volta.
  defp aguardar(condicao, mensagem) do
    aguardar_ate(condicao, mensagem, System.monotonic_time(:millisecond) + @espera)
  end

  defp aguardar_ate(condicao, mensagem, limite) do
    cond do
      condicao.() ->
        :ok

      System.monotonic_time(:millisecond) > limite ->
        flunk("espera esgotada: #{mensagem}")

      true ->
        Process.sleep(1)
        aguardar_ate(condicao, mensagem, limite)
    end
  end

  # Derruba a instância: o dono suspenso não impede o sinal de saída, e a limpeza não
  # pode fazer o teste falhar.
  defp parar(sup) do
    try do
      if Process.alive?(sup), do: Supervisor.stop(sup, :normal, 5_000)
    catch
      :exit, _reason -> :ok
    end
  end
end
