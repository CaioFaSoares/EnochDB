defmodule Enoch.Instance.Boot do
  @moduledoc """
  A sequência de subida em sete passos (D34, R31).

  Cada instância sobe a própria árvore de supervisão — dono das tabelas, admissão
  e transactor (ver `Enoch.Instance.Supervisor`) — e `Enoch.start_link/1` chama a
  subida logo depois, com o processo que chamou. A subida é `run/2`:

  1. confere a versão do layout do storage aberto e recusa um layout mais novo que
     o conhecido (`Enoch.Storage.layout_version/0`);
  2. confere que o estado atual e o log concordam e reconstrói o atual se
     divergirem — é a conferência do adaptador (`Enoch.Adapters.Memory.verify/1`
     no `Memory`), chamada no caminho interno da subida;
  3. garante a admissão fechada a chamadores externos: o transactor sobe com a
     árvore e o único caminho que escreve durante os passos seguintes é o interno
     (`Enoch.Transactor.transact/3` com `:internal`);
  4. registra as funções de transação e as regras das listas de módulos das
     opções, recusando dois módulos que registrem o mesmo nome;
  5. instalar o schema fica na s02;
  6. aplicar as migrações pendentes fica na s05;
  7. abre a admissão (quando a instância subiu para ficar aberta) e emite a
     telemetria da subida com a base (`Enoch.Telemetry.boot/2`).

  Uma falha em qualquer passo interrompe a subida com erro explícito e a admissão
  continua fechada: `Enoch.start_link/1` derruba a árvore e devolve o erro. Não há
  gancho de subida para a aplicação (D34).

  ## O registro genérico do passo 4

  O registro de funções e regras mora aqui até haver `schema/registry.ex` (s02) e
  `query/rules.ex` (s03). A instância recebe as listas nas opções (D35, R24):

      Enoch.start_link(
        name: ...,
        adapter: ...,
        schema: [MyApp.Schema],        # cada módulo expõe `schema/0`
        functions: [MyApp.Fns],        # cada módulo expõe `functions/0`
        rules: [Ledger.Rules]          # cada módulo expõe `rules/0`
      )

  Uma lista de funções aceita o módulo agregador — que expõe `functions/0`
  devolvendo pares `{nome, módulo}` — ou o próprio par `{nome, módulo}`, sendo o
  módulo o que implementa `Enoch.Tx.Function` (D35). Uma lista de regras aceita
  módulos que expõem `rules/0` com definições que trazem um `:name` (nome,
  argumentos e corpo, D35). Os nomes têm espaço de nomes. Dois pares de função com
  o mesmo nome, ou duas definições de regra com o mesmo nome, impedem a subida com
  `{:duplicate_function, nome, módulo_anterior, módulo_novo}` ou
  `{:duplicate_rule, nome, módulo_anterior, módulo_novo}`. Os módulos de schema
  entram no registro como a lista recebida; o passo que os instala é da s02.

  O registro devolvido por `run/2` é `%{schema: [módulo], functions: %{nome =>
  módulo}, rules: %{nome => módulo}}`. Nada o consome ainda nesta sprint; a s02 o
  liga ao transactor.

  Referências: `docs/arquitetura.md` (`instance/boot.ex`), ADR-0008 e a spec em
  `docs/_sprints/s01-nucleo-enoch/03_spec/handovers/spec.md` (R17, R24, R31).
  """

  alias Enoch.DB
  alias Enoch.Instance.Admission
  alias Enoch.Instance.Owner
  alias Enoch.Instance.Supervisor
  alias Enoch.Telemetry

  @typedoc """
  O registro genérico das listas de módulos da instância (passo 4, D35).
  """
  @type registry :: %{
          schema: [module()],
          functions: %{atom() => module()},
          rules: %{atom() => module()}
        }

  @doc """
  Executa a sequência de subida de uma instância já no ar.

  Recebe o nome da instância e as opções de `Enoch.start_link/1` (`:adapter`,
  `:schema`, `:functions`, `:rules` e `:admission`). Devolve `{:ok, registro}` com
  o registro do passo 4, ou `{:error, motivo}` com o erro explícito do primeiro
  passo que falhar — a admissão fica fechada em qualquer falha.

  É chamada por `Enoch.start_link/1`; quem sobe a árvore por
  `Enoch.Instance.Supervisor.start_link/1` a chama quando quiser subir a instância.
  """
  @spec run(term(), keyword()) :: {:ok, registry()} | {:error, term()}
  def run(instance, opts) do
    owner = Supervisor.owner(instance)
    adapter = Keyword.fetch!(opts, :adapter)
    storage = Owner.storage(owner)

    with :ok <- Admission.close(instance),
         :ok <- check_layout(adapter, storage),
         :ok <- verify_state(adapter, storage),
         {:ok, registry} <- register(opts),
         :ok <- open(instance, opts),
         :ok <- emit(instance, owner) do
      {:ok, registry}
    end
  end

  # Passo 1: a versão do layout do storage aberto contra a que este pacote conhece
  # (D34). Um layout mais novo impede a subida.
  defp check_layout(adapter, storage) do
    known = Enoch.Storage.layout_version()
    stored = layout_version(adapter, storage)

    if stored > known do
      {:error, {:layout_too_new, stored, known}}
    else
      :ok
    end
  end

  # A versão do layout é opcional no contrato: um adaptador que não persiste
  # layout, como o `Memory`, reporta a versão conhecida. `function_exported?/3`
  # vale porque `open/1` já carregou o módulo.
  defp layout_version(adapter, storage) do
    if function_exported?(adapter, :layout_version, 1) do
      adapter.layout_version(storage)
    else
      Enoch.Storage.layout_version()
    end
  end

  # Passo 2: a conferência do estado atual contra o log é do adaptador — só ele
  # conhece as tabelas e o contador — e é ele que reconstrói o atual se divergir
  # (`Enoch.Adapters.Memory.verify/1` no `Memory`). Um adaptador sem a conferência
  # não tem o que reconstruir.
  defp verify_state(adapter, storage) do
    if function_exported?(adapter, :verify, 1) do
      adapter.verify(storage)
    end

    :ok
  end

  # Passo 4: as listas de módulos viram o registro, com colisão de nome recusada.
  defp register(opts) do
    with {:ok, functions} <-
           collect(
             Keyword.get(opts, :functions, []),
             &function_definitions/1,
             :duplicate_function
           ),
         {:ok, rules} <-
           collect(Keyword.get(opts, :rules, []), &rule_definitions/1, :duplicate_rule) do
      {:ok, %{schema: Keyword.get(opts, :schema, []), functions: functions, rules: rules}}
    end
  end

  # Passo 7: abre a admissão quando a instância subiu para ficar aberta. A opção
  # `:status` da admissão é o estado desejado ao fim da subida: `:closed` — o
  # padrão é `:open` — deixa a instância fechada a chamadores externos, para
  # manutenção ou para o teste dos estados.
  defp open(instance, opts) do
    if desired_status(opts) == :open, do: Admission.open(instance)

    :ok
  end

  defp desired_status(opts) do
    opts |> Keyword.get(:admission, []) |> Keyword.get(:status, :open)
  end

  # Passo 7: a telemetria da subida, com a base publicada pelo transactor.
  defp emit(instance, owner) do
    base = owner |> Owner.db() |> DB.basis_t()
    Telemetry.boot(base, instance)
  end

  # --- o registro genérico -----------------------------------------------------

  # Cada entrada da lista é lida para uma lista de pares `{nome, módulo}`, e os
  # pares entram no registro; um nome repetido é erro explícito.
  defp collect(entries, read, tag) do
    Enum.reduce_while(entries, {:ok, %{}}, fn entry, {:ok, acc} ->
      with {:ok, definitions} <- read.(entry),
           {:ok, acc} <- put_definitions(acc, definitions, tag) do
        {:cont, {:ok, acc}}
      else
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp put_definitions(acc, definitions, tag) do
    Enum.reduce_while(definitions, {:ok, acc}, fn {name, module}, {:ok, acc} ->
      case acc do
        %{^name => previous} -> {:halt, {:error, {tag, name, previous, module}}}
        _ -> {:cont, {:ok, Map.put(acc, name, module)}}
      end
    end)
  end

  # Uma entrada de `functions:` é o par `{nome, módulo}` direto ou um módulo que
  # expõe a lista de pares em `functions/0`.
  defp function_definitions({name, module}) when is_atom(name), do: {:ok, [{name, module}]}

  defp function_definitions(module) when is_atom(module) do
    with {:ok, list} <- exposed(module, :functions) do
      normalize_functions(list)
    end
  end

  defp function_definitions(other), do: {:error, {:invalid_function, other}}

  defp normalize_functions(list) when is_list(list) do
    if Enum.all?(list, &match?({name, module} when is_atom(name) and is_atom(module), &1)) do
      {:ok, list}
    else
      {:error, {:invalid_functions, list}}
    end
  end

  defp normalize_functions(other), do: {:error, {:invalid_functions, other}}

  # Uma entrada de `rules:` é um módulo que expõe a lista de definições em
  # `rules/0`; cada definição é um mapa ou keyword com o `:name`.
  defp rule_definitions(module) when is_atom(module) do
    with {:ok, list} <- exposed(module, :rules) do
      normalize_rules(list, module)
    end
  end

  defp rule_definitions(other), do: {:error, {:invalid_rules, other}}

  defp normalize_rules(list, module) when is_list(list) do
    list
    |> Enum.reduce_while({:ok, []}, fn definition, {:ok, acc} ->
      case rule_name(definition) do
        {:ok, name} -> {:cont, {:ok, [{name, module} | acc]}}
        :error -> {:halt, {:error, {:invalid_rule, definition}}}
      end
    end)
    |> case do
      {:ok, definitions} -> {:ok, Enum.reverse(definitions)}
      {:error, _} = error -> error
    end
  end

  defp normalize_rules(other, _module), do: {:error, {:invalid_rules, other}}

  defp rule_name(%{} = definition) do
    case Map.fetch(definition, :name) do
      {:ok, name} when is_atom(name) -> {:ok, name}
      _ -> :error
    end
  end

  defp rule_name(list) when is_list(list) do
    case Keyword.fetch(list, :name) do
      {:ok, name} when is_atom(name) -> {:ok, name}
      _ -> :error
    end
  end

  defp rule_name(_definition), do: :error

  defp exposed(module, fun) do
    if Code.ensure_loaded?(module) and function_exported?(module, fun, 0) do
      {:ok, apply(module, fun, [])}
    else
      {:error, {:invalid_module, fun, module}}
    end
  end
end
