# test/support/

**Propósito:** Auxiliares de teste: o `test_adapter.ex`, o adaptador externo que roda a suíte de contrato de fora de `lib/enoch/adapters` (D24, R25), e o `boot_adapter.ex`, o adaptador dos passos 1 e 2 da subida. Os geradores de propriedades entram na fatia que os pedir.

**Decisões:** D38, D36, D13. Texto em [`../../docs/_sprints/s01-nucleo-enoch/01_grilling/handovers/decisoes.md`](../../docs/_sprints/s01-nucleo-enoch/01_grilling/handovers/decisoes.md).

**Sprint:** s01 em diante.

**Fronteira:** Nada daqui entra no pacote publicado.

**Ponto de extensão:** Não.

**Origem:** issue [#1](https://github.com/CaioFaSoares/EnochDB/issues/1) e o mapa em [`../../docs/arquitetura.md`](../../docs/arquitetura.md). Vocabulário em [`../../CONTEXT.md`](../../CONTEXT.md). As issues [#3](https://github.com/CaioFaSoares/EnochDB/issues/3) e [#11](https://github.com/CaioFaSoares/EnochDB/issues/11) trouxeram os dois adaptadores.
