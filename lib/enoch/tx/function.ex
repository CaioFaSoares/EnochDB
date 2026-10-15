defmodule Enoch.Tx.Function do
  @moduledoc """
  O behaviour das funções de transação (D35, R24, R12).

  Uma função de transação é um módulo que implementa este behaviour e é
  registrado por nome no passo 4 da subida (D34), num par `{nome, módulo}` que o
  módulo agregador da aplicação expõe (ver `Enoch.Instance.Boot`). Os nomes têm
  espaço de nomes, como os atributos: `ledger/post`, `ledger/balance`. Um nome
  pode ser chamado de dentro de uma transação — `[:"ledger/post", dados]` —, e o
  transactor o resolve pelo registro (s02).

  Nesta sprint o módulo é **só o behaviour**: nenhum módulo o implementa no pacote
  e nada o chama ainda. A s02 implementa o registro e a chamada (dentro do
  transactor, resolvendo o nome), e a s05 aplica o processo próprio com tempo e
  heap limitados, cuja morte aborta só aquela transação (D21). A forma exata do
  retorno e dos argumentos fica com quem a chama; o que o registrador usa hoje é o
  nome do par `{nome, módulo}`.

  Referências: `docs/arquitetura.md` (`tx/function.ex`), `lib/enoch/tx/CONTEXT.md`,
  ADR-0007 e a spec em `docs/_sprints/s01-nucleo-enoch/03_spec/handovers/spec.md`
  (R12, R24).
  """

  @doc """
  Executa a função de transação sobre os argumentos da chamada.

  A chamada recebe, como argumento, os dados que vieram junto do nome na
  transação — em `[:"ledger/post", dados]`, o `dados` — e devolve o que a
  transação deve aplicar. A forma exata do argumento e do retorno é fixada na s02,
  quando o transactor passa a resolver e chamar as funções.
  """
  @callback call(args :: term()) :: term()
end
