# 01_grilling — esclarecer e decidir

## Objetivo

Transformar o pedido ou a hipótese de entrada em decisões que o dono reconheça como suas. Nenhum código ou ticket é produzido nesta etapa.

## Entradas

- Material específico desta execução em `docs/_sprints/{sprint}/01_grilling/inputs/`.
- [`../../CONTEXT.md`](../../CONTEXT.md) (raiz do repositório): vocabulário aprovado.
- `../canon.md` e `../adr/`: decisões vigentes e alternativas já avaliadas.
- Links para material histórico, sem copiar conteúdo de outras fontes.

## Processo

1. Identifique atores, necessidade, restrições e resultado observável.
2. Interrogue ambiguidades até cada ponto ser uma decisão fechada, descartado com motivo, ou aberto com a informação que falta.
3. Sinalize qualquer conflito com o canon ou um ADR; não substitua decisão vigente em silêncio.
4. Registre as três listas em `handovers/decisoes.md`, com caminhos para as fontes lidas.

## Saída e gate humano

Saída: `docs/_sprints/{sprint}/01_grilling/handovers/decisoes.md`.

Antes do gate humano, rode o gate `grilling` ([`../agents/jev.md`](../agents/jev.md)) e leve o `recibo` ao dono.

O dono lê e confirma as decisões fechadas. Se alguma parecer invenção do agente, ela volta à discussão. Só após esse aceite a ficha pode fechar.

## Quando não se aplica

Pode ser `nao-aplicavel` quando o trabalho já chega com decisões aprovadas e rastreáveis, sem pergunta de produto ou arquitetura. A ficha deve apontar essa fonte. Não use essa exceção para evitar uma decisão difícil.
