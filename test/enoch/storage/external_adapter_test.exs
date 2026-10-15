defmodule Enoch.Storage.Contract.ExternalAdapterTest do
  @moduledoc """
  A suíte de contrato rodando em um adaptador de fora de `lib/enoch/adapters`.

  O adaptador é o `Enoch.TestAdapter`, de `test/support/`: o caso prova que a
  suíte é reutilizável por uma extensão de storage que mora fora do pacote (D24,
  R25).
  """

  use Enoch.Storage.ContractCase,
    adapter: Enoch.TestAdapter,
    storage_opts: [max_memory: :infinity]
end
