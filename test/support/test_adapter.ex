defmodule Enoch.TestAdapter do
  @moduledoc """
  Adaptador de teste que delega ao `Enoch.Adapters.Memory`.

  Existe para a suíte de contrato rodar em um adaptador que **não** mora em
  `lib/enoch/adapters`, como um adaptador externo o faria (D24, R25): o módulo só
  implementa o behaviour `Enoch.Storage` e repassa as chamadas. Não entra no
  pacote publicado (`mix.exs`, `elixirc_paths/1`).
  """

  @behaviour Enoch.Storage

  defdelegate open(opts), to: Enoch.Adapters.Memory
  defdelegate db(storage), to: Enoch.Adapters.Memory
  defdelegate append(storage, datoms), to: Enoch.Adapters.Memory
  defdelegate scan_eavt(db, opts), to: Enoch.Adapters.Memory
  defdelegate scan_aevt(db, opts), to: Enoch.Adapters.Memory
  defdelegate scan_avet(db, opts), to: Enoch.Adapters.Memory
  defdelegate scan_vaet(db, opts), to: Enoch.Adapters.Memory
end
