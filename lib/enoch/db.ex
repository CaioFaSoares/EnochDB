defmodule Enoch.DB do
  @moduledoc """
  O banco como valor: `{referências, basis_t}` (D16, D18).

  Criar um banco como valor é O(1): ele guarda as referências que o adaptador
  precisa para varrer — e não os dados — e a base, o número de ordem da última
  transação visível a ele. Consultas contra o mesmo valor dão sempre o mesmo
  resultado, e o valor sobrevive a transações posteriores: é o que a varredura
  usa para escolher entre o estado atual e o histórico (ver `Enoch.Storage`).

  O valor é opaco: quem precisa das partes usa `refs/1` e `basis_t/1`, e quem
  constrói um valor de outra base — o `as_of` da s03 — usa `new/2` com as mesmas
  referências.

  Referências: `docs/arquitetura.md` (`db.ex`), `docs/adr/0002-*.md` e
  `docs/adr/0003-*.md`. Vocabulário em `CONTEXT.md`.
  """

  @typedoc "Número de ordem da última transação visível ao banco como valor."
  @type basis_t :: non_neg_integer()

  @typedoc """
  Banco como valor: as referências que a varredura precisa e a base.

  As referências são opacas e do adaptador; no `Memory` são as duas tabelas ETS e
  o contador.
  """
  @opaque t :: {refs :: term(), basis_t()}

  @doc "Constrói um banco como valor sobre referências já abertas, numa base."
  @spec new(term(), basis_t()) :: t()
  def new(refs, basis_t), do: {refs, basis_t}

  @doc "As referências que a varredura usa."
  @spec refs(t()) :: term()
  def refs({refs, _basis_t}), do: refs

  @doc "A base do banco como valor."
  @spec basis_t(t()) :: basis_t()
  def basis_t({_refs, basis_t}), do: basis_t
end
