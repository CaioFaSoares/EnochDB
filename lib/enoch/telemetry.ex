defmodule Enoch.Telemetry do
  @moduledoc """
  Os eventos de `:telemetry` do Enoch (D21, D27, D34, R17).

  A telemetria é o caminho de fora para medir a instância sem acoplar o chamador
  ao núcleo: quem quiser observa com `:telemetry.attach/4` no prefixo dos eventos,
  e o núcleo só emite. O evento da **subida** entra na s01 (passo 7 da sequência,
  D34): ao abrir a admissão, a instância publica a base com que subiu.

  ## Eventos

  | Evento | Quando | Medidas | Metadados | Sprint |
  | --- | --- | --- | --- | --- |
  | `[:enoch, :boot]` | no passo 7 da subida | `%{basis_t: base}` | `%{instance: nome}` | s01 |

  Os demais eventos da R17 — memória usada, consultas mortas por limite,
  transações rejeitadas por cota, linhas lidas por varredura, tamanho da fila e
  transações por segundo — entram na s05, junto com a cota e os limites da D20 e
  da D21. O contador de linhas lidas já existe desde a s01 no contrato
  (`Enoch.Storage.rows_read/1`); o evento dele é da s05.

  Referências: `docs/_sprints/s01-nucleo-enoch/03_spec/handovers/spec.md` (R17),
  `docs/adr/0004-*.md` (telemetria da fila) e `docs/adr/0008-*.md` (passo 7).
  """

  @boot [:enoch, :boot]

  @doc """
  O nome do evento da subida (passo 7, D34, R17).
  """
  @spec boot_event() :: [atom()]
  def boot_event, do: @boot

  @doc """
  Emite a telemetria da subida com a base (passo 7, D34, R17).

  `base` é o `basis_t` da instância quando a admissão abre, e `instance` é o nome
  dela. A emissão nunca falha: um observador com erro não derruba a subida.
  """
  @spec boot(Enoch.DB.basis_t(), term()) :: :ok
  def boot(base, instance) do
    :telemetry.execute(@boot, %{basis_t: base}, %{instance: instance})
  end
end
