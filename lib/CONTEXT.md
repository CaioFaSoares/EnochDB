# lib/

**Propósito:** Código-fonte do pacote `enoch`. Guarda o módulo raiz `lib/enoch.ex` (API pública funcional por nome de instância) e a pasta `enoch/`.

**Decisões:** D23 (pacote único), D32 (API pública). Texto em [`../docs/_sprints/s01-nucleo-enoch/01_grilling/handovers/decisoes.md`](../docs/_sprints/s01-nucleo-enoch/01_grilling/handovers/decisoes.md).

**Sprint:** s01 cria o esqueleto do módulo raiz; s03 acrescenta `q`, `pull`, `as_of` e `history`.

**Fronteira:** Só o módulo raiz mora aqui. Toda região arquitetural mora em `lib/enoch/`.

**Ponto de extensão:** Não.

**Origem:** issue [#1](https://github.com/CaioFaSoares/EnochDB/issues/1) e o mapa em [`../docs/arquitetura.md`](../docs/arquitetura.md). Vocabulário em [`../CONTEXT.md`](../CONTEXT.md). Esta pasta ainda não tem código; este arquivo é a orientação para a implementação.
