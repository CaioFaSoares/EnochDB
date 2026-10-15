defmodule Enoch.Application do
  @moduledoc """
  App OTP `:enoch`: sobe só o que é global ao nó.

  O único processo global é o registro das instâncias (`Enoch.InstanceRegistry`),
  que guarda o nome de cada árvore de instância e dos seus filhos (ver
  `Enoch.Instance.Supervisor`). Cada instância sobe a própria árvore fora daqui, a
  partir das opções de subida.

  Referências: `docs/arquitetura.md` (`application.ex`) e ADR-0007.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [{Registry, keys: :unique, name: Enoch.InstanceRegistry}]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
