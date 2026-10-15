defmodule Enoch.Repo do
  @moduledoc """
  A macro `use Enoch.Repo`: a camada fina que delega ao núcleo funcional.

  A API do Enoch é funcional por nome de instância (ADR-0007): `Enoch.start_link/1`
  sobe a instância com o nome dado e as chamadas seguintes recebem esse nome.
  `use Enoch.Repo` gera as mesmas funções delegando ao núcleo, com o módulo do repo
  como nome da instância:

      defmodule MyApp.Db do
        use Enoch.Repo
      end

      {:ok, _} =
        Enoch.start_link(
          name: MyApp.Db,
          adapter: Enoch.Adapters.Memory,
          storage_opts: [max_memory: :infinity]
        )

      {:ok, 1} = MyApp.Db.transact([[:add, 100, 10, 7]])
      MyApp.Db.db()

  A camada não tem lógica própria: cada função só chama a equivalente do núcleo com
  `__MODULE__`. O ganho é o nome — `MyApp.Db.transact/1` em vez de
  `Enoch.transact(MyApp.Db, ...)` — e a forma de o módulo virar o repo de uma
  aplicação, como no Ecto. Um banco por tenant e o `:memory:` por teste continuam
  sem módulo próprio, pela API funcional (D32).

  Nesta fatia a macro gera `transact/1` e `db/0`, as duas funções que o núcleo já
  expõe. `q`, `pull`, `as_of` e `history` entram com a API da s03 (D22, D32).

  A configuração no `use Enoch.Repo` — as listas `schema:`, `functions:` e `rules:`
  e a descoberta de extensões — é da s02 e do e02 (D24, D34): a instância sobe pelo
  `Enoch.start_link/1` com o módulo do repo como nome.

  Referências: `docs/arquitetura.md` (`repo.ex`), ADR-0007 e a spec em
  `docs/_sprints/s01-nucleo-enoch/03_spec/handovers/spec.md` (R30).
  """

  @doc """
  Gera as funções do repo delegando ao núcleo pelo nome da instância.

  O módulo que faz `use Enoch.Repo` é o nome da instância. A macro não aceita
  opções nesta sprint: uma opção passada aqui seria ignorada em silêncio, e as
  listas de módulos e a configuração do repo só têm uso depois do instalador da s02
  e do registro de extensões do e02 (D24, D34).
  """
  defmacro __using__(opts) do
    if opts != [] do
      raise ArgumentError,
            "use Enoch.Repo não aceita opções nesta sprint, recebi: #{Macro.to_string(opts)}"
    end

    quote do
      @doc """
      Aplica uma transação crua à instância do repo e devolve o `t` gravado.

      Ver `Enoch.transact/2`: as operações são `[:add, e, a, v]` e
      `[:retract, e, a, v]` (R11, só o cru nesta sprint) e a escrita passa pela
      admissão limitada (R13).
      """
      @spec transact([Enoch.Transactor.operation()]) ::
              {:ok, Enoch.Storage.tx()} | {:error, term()}
      def transact(operations), do: Enoch.transact(__MODULE__, operations)

      @doc """
      O banco como valor da instância do repo, na base publicada (D16, D18).

      Ver `Enoch.db/1`; a base se lê com `Enoch.DB.basis_t/1`.
      """
      @spec db() :: Enoch.DB.t()
      def db, do: Enoch.db(__MODULE__)
    end
  end
end
