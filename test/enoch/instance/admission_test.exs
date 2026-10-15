defmodule Enoch.Instance.AdmissionTest do
  @moduledoc """
  A admissão limitada de uma instância: o limite, os estados fechado e aberto e a
  reconciliação com a caixa do transactor (R13, D27, D34; issue #6).

  O que o teste prova, pelo caminho real — `Enoch.start_link/1` sobe a árvore, a
  admissão nasce com o contador e a escrita passa pelo `Enoch.Transactor` — é o que a
  issue pede:

  1. acima do limite o chamador é rejeitado antes de a mensagem entrar na caixa e o
     incremento do rejeitado é desfeito;
  2. com a admissão fechada a escrita externa é rejeitada e a interna da subida passa;
  3. a queda do transactor zera o contador de admissão no `init` do novo;
  4. um chamador morto entre incrementar e enviar deixa o contador igual à caixa real
     depois da reconciliação por `message_queue_len`.

  A medida da caixa é `Process.info(pid, :message_queue_len)` e a do contador é
  `Enoch.Instance.Admission.counter/1`. O transactor é suspenso com `:sys.suspend`
  quando o teste precisa da mensagem parada na caixa e retomado na mesma sequência
  (o `call` tem o tempo limite de quinze segundos de `docs/canon/chat.md`). O arquivo é
  síncrono porque mexe na caixa e na vida do transactor de verdade.

  Referências: `docs/_sprints/s01-nucleo-enoch/03_spec/handovers/spec.md` (R13),
  `docs/adr/0004-*.md`, `docs/adr/0008-*.md` e `docs/arquitetura.md`
  (`instance/admission.ex`).
  """

  use ExUnit.Case, async: false

  alias Enoch.Adapters.Memory
  alias Enoch.DB
  alias Enoch.Instance.Admission
  alias Enoch.Instance.Supervisor, as: InstanceSupervisor

  @storage_opts [max_memory: :infinity]
  @attr 10

  describe "limite de admissão" do
    test "o contador acompanha as transações em andamento e volta a zero" do
      nome = subir(limit: 4)
      transactor = suspender(nome)

      assert Admission.counter(nome) == 0

      em_voo = Task.async(fn -> Enoch.transact(nome, [[:add, 1, @attr, 7]]) end)
      assert aguardar(fn -> caixa(transactor) == 1 end)
      assert Admission.counter(nome) == 1

      assert :ok = :sys.resume(transactor)
      assert Task.await(em_voo) == {:ok, 1}
      assert Admission.counter(nome) == 0
      assert caixa(transactor) == 0
    end

    test "acima do limite o chamador é rejeitado antes de a mensagem entrar na caixa" do
      nome = subir(limit: 1)
      transactor = suspender(nome)

      assert Admission.limit(nome) == 1

      em_voo = Task.async(fn -> Enoch.transact(nome, [[:add, 100, @attr, 7]]) end)
      assert aguardar(fn -> caixa(transactor) == 1 end)
      assert Admission.counter(nome) == 1

      # O limite é um: a segunda chamada é rejeitada no processo de quem chama, antes
      # de a mensagem entrar na caixa.
      assert {:error, :admission_full} = Enoch.transact(nome, [[:add, 200, @attr, 8]])

      # A caixa continua com a única mensagem admitida e o contador volta ao valor de
      # antes da rejeição — o incremento do rejeitado foi desfeito.
      assert caixa(transactor) == 1
      assert Admission.counter(nome) == 1

      assert :ok = :sys.resume(transactor)
      assert Task.await(em_voo) == {:ok, 1}
      assert Admission.counter(nome) == 0
      assert DB.basis_t(Enoch.db(nome)) == 1
    end
  end

  describe "estados fechado e aberto" do
    test "fechada, a escrita externa é rejeitada e a interna da subida passa" do
      nome = subir(status: :closed, limit: 4)
      transactor = transactor(nome)

      assert Admission.status(nome) == :closed

      assert {:error, :admission_closed} = Enoch.transact(nome, [[:add, 1, @attr, 7]])
      assert caixa(transactor) == 0
      assert Admission.counter(nome) == 0
      assert DB.basis_t(Enoch.db(nome)) == 0

      # O caminho interno da subida (passo 3, D34) escreve com a admissão fechada.
      assert {:ok, 1} = Enoch.Transactor.transact(nome, [[:add, 1, @attr, 7]], :internal)
      assert DB.basis_t(Enoch.db(nome)) == 1
      assert Admission.counter(nome) == 0

      # O passo 7 abre a admissão e a escrita externa volta a passar.
      assert :ok = Admission.open(nome)
      assert Admission.status(nome) == :open
      assert {:ok, 2} = Enoch.transact(nome, [[:add, 2, @attr, 8]])
      assert DB.basis_t(Enoch.db(nome)) == 2

      # Uma falha na subida a deixa fechada: fechada de novo, o externo é rejeitado.
      assert :ok = Admission.close(nome)
      assert Admission.status(nome) == :closed
      assert {:error, :admission_closed} = Enoch.transact(nome, [[:add, 3, @attr, 9]])
      assert DB.basis_t(Enoch.db(nome)) == 2
    end

    test "o padrão é aberta, com limite 32" do
      nome = subir([])
      assert Admission.status(nome) == :open
      assert Admission.limit(nome) == 32
      assert Admission.counter(nome) == 0
    end

    test "limite e estado inválidos impedem a subida da instância" do
      # `start_link` liga a árvore a quem chama: com o processo preso à saída da
      # árvore (trap_exit), o `start_link` de uma subida que falha devolve o motivo em
      # vez de derrubar quem chamou.
      Process.flag(:trap_exit, true)

      assert {:error,
              {:shutdown, {:failed_to_start_child, Admission, {:invalid_admission_limit, 0}}}} =
               iniciar(admission: [limit: 0])

      assert {:error,
              {:shutdown, {:failed_to_start_child, Admission, {:invalid_admission_status, :meio}}}} =
               iniciar(admission: [status: :meio])
    end
  end

  describe "queda do transactor" do
    test "o init do transactor novo zera o contador de admissão" do
      nome = subir(limit: 4)
      pai = self()
      transactor = suspender(nome)
      dono = pid(InstanceSupervisor.owner(nome))
      ref = Admission.ref(nome)

      # Uma transação admitida fica na caixa do transactor suspenso; quando ele morre,
      # a mensagem morre com ele e nada a decrementa. É o vazamento que a D27 manda o
      # `init` do transactor novo zerar.
      chamador =
        spawn(fn ->
          resultado =
            try do
              Enoch.transact(nome, [[:add, 1, @attr, 7]])
            catch
              :exit, motivo -> {:exit, motivo}
            end

          send(pai, {:resultado, resultado})
        end)

      assert aguardar(fn -> caixa(transactor) == 1 end)
      assert Admission.counter(nome) == 1

      Process.exit(transactor, :kill)

      novo = aguardar_pid(InstanceSupervisor.transactor(nome), transactor)
      assert Process.alive?(novo)
      assert Admission.counter(nome) == 0

      # O contador vive na admissão e o dono das tabelas segue vivo: só o transactor
      # caiu.
      assert Admission.ref(nome) == ref
      assert pid(InstanceSupervisor.owner(nome)) == dono

      # A transação que morreu na caixa nunca foi gravada e o chamador dela recebeu a
      # saída; a escrita seguinte roda no transactor novo.
      assert_receive {:resultado, {:exit, _motivo}}, 1_000
      assert {:ok, 1} = Enoch.transact(nome, [[:add, 5, @attr, 7]])
      assert Admission.counter(nome) == 0
      assert DB.basis_t(Enoch.db(nome)) == 1

      refute Process.alive?(chamador)
    end
  end

  describe "reconciliação por message_queue_len" do
    test "chamador morto entre incrementar e enviar: o contador fica igual à caixa" do
      nome = subir(limit: 1)
      transactor = transactor(nome)
      ref = Admission.ref(nome)

      matar_entre_incrementar_e_enviar(ref)

      # A unidade presa: incrementada e nunca enviada, a caixa segue vazia.
      assert Admission.counter(nome) == 1
      assert caixa(transactor) == 0

      # Com o limite 1, a unidade presa barra a admissão direta (sem reconciliar) — e o
      # rejeitado desfaz o incremento dele, sem mexer na unidade presa.
      assert {:error, :admission_full} = Admission.admit(ref)
      assert Admission.counter(nome) == 1

      # A reconciliação deixa o contador igual à caixa real.
      assert Admission.reconcile(nome) == :ok
      assert Admission.counter(nome) == 0
      assert Admission.counter(nome) == caixa(transactor)

      # É o que o caminho da escrita faz antes de admitir: a escrita nova passa.
      assert {:ok, 1} = Enoch.transact(nome, [[:add, 1, @attr, 7]])
      assert Admission.counter(nome) == caixa(transactor)
      assert DB.basis_t(Enoch.db(nome)) == 1
    end

    test "com uma transação em voo, a reconciliação deixa o contador igual à caixa" do
      nome = subir(limit: 8)
      transactor = suspender(nome)
      ref = Admission.ref(nome)

      em_voo = Task.async(fn -> Enoch.transact(nome, [[:add, 1, @attr, 7]]) end)
      assert aguardar(fn -> caixa(transactor) == 1 end)

      matar_entre_incrementar_e_enviar(ref)
      assert Admission.counter(nome) == 2
      assert caixa(transactor) == 1

      assert Admission.reconcile(nome) == :ok
      assert Admission.counter(nome) == 1
      assert Admission.counter(nome) == caixa(transactor)

      assert :ok = :sys.resume(transactor)
      assert Task.await(em_voo) == {:ok, 1}
      assert Admission.counter(nome) == 0
      assert caixa(transactor) == 0
    end
  end

  # O passo exato de `Enoch.Transactor.transact/3`: incrementar e só então enviar. O
  # processo que faz isso morre no meio, sem enviar nada.
  defp matar_entre_incrementar_e_enviar(ref) do
    pai = self()

    chamador =
      spawn(fn ->
        :ok = Admission.admit(ref)
        send(pai, :incrementado)

        receive do
          :enviar -> :ok
        end
      end)

    assert_receive :incrementado, 1_000
    monitor = Process.monitor(chamador)
    Process.exit(chamador, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^chamador, :killed}, 1_000
    :ok
  end

  defp iniciar(opcoes) do
    Enoch.start_link(
      Keyword.merge(
        [name: nome_unico(), adapter: Memory, storage_opts: @storage_opts],
        opcoes
      )
    )
  end

  defp subir(admissao) do
    nome = nome_unico()

    assert {:ok, sup} =
             Enoch.start_link(
               name: nome,
               adapter: Memory,
               storage_opts: @storage_opts,
               admission: admissao
             )

    on_exit(fn -> parar(sup) end)
    nome
  end

  defp parar(sup) do
    try do
      if Process.alive?(sup), do: Supervisor.stop(sup, :normal, 5_000)
    catch
      :exit, _motivo -> :ok
    end
  end

  defp nome_unico, do: :"admissao_#{System.unique_integer([:positive])}"

  defp transactor(nome), do: pid(InstanceSupervisor.transactor(nome))

  defp suspender(nome) do
    transactor = transactor(nome)
    :ok = :sys.suspend(transactor)
    on_exit(fn -> retomar(transactor) end)
    transactor
  end

  defp retomar(transactor) do
    if Process.alive?(transactor) do
      try do
        :sys.resume(transactor)
      catch
        :exit, _motivo -> :ok
      end
    end

    :ok
  end

  defp pid(nome_registrado), do: GenServer.whereis(nome_registrado)

  defp caixa(transactor) do
    case Process.info(transactor, :message_queue_len) do
      {:message_queue_len, tamanho} -> tamanho
      nil -> :sem_transactor
    end
  end

  defp aguardar(condicao, tentativas \\ 400) do
    cond do
      condicao.() ->
        true

      tentativas == 0 ->
        false

      true ->
        Process.sleep(5)
        aguardar(condicao, tentativas - 1)
    end
  end

  defp aguardar_pid(nome_registrado, antigo, tentativas \\ 400) do
    novo = pid(nome_registrado)

    cond do
      is_pid(novo) and novo != antigo and Process.alive?(novo) ->
        novo

      tentativas == 0 ->
        flunk("o transactor não voltou depois da queda")

      true ->
        Process.sleep(5)
        aguardar_pid(nome_registrado, antigo, tentativas - 1)
    end
  end
end
