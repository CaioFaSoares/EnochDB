defmodule Enoch.Storage.Contract.MemoryTest do
  @moduledoc """
  A suíte de contrato rodando no adaptador do pacote.

  As opções são as obrigatórias do `Memory`: o `max_memory` (D20). O valor é
  ignorado até a cota da s05; aqui só prova que o adaptador sobe com ele.
  """

  use Enoch.Storage.ContractCase,
    adapter: Enoch.Adapters.Memory,
    storage_opts: [max_memory: :infinity]
end
