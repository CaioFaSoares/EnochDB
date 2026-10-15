# test/enoch/instance/

**Propósito:** Os testes da instância: a admissão limitada de cada instância — o limite, os estados fechado e aberto, a queda do transactor e a reconciliação do contador com a caixa (`admission_test.exs`) — e, nas fatias seguintes, a subida em sete passos.

**Decisões:** D27 (contador em `:atomics`, rejeição antes da caixa, vazamento do contador), D34 (estado fechado na subida e aberto no passo 7), D21. Texto em [`../../../docs/_sprints/s01-nucleo-enoch/01_grilling/handovers/decisoes.md`](../../../docs/_sprints/s01-nucleo-enoch/01_grilling/handovers/decisoes.md).

**Sprint:** s01: admissão limitada e os dois estados. s05: a telemetria da admissão. A subida (passo 4, 5 e 6) entra com as fatias da s02 e da s05.

**Fronteira:** Não é a suíte de contrato do adaptador (essa é `../storage/`) nem o teste da recuperação da escrita (esse é `../adapters/memory_recovery_test.exs`, da ADR-0003); aqui o que se mede é a contabilidade da admissão e o caminho de escrita que a usa.

**Ponto de extensão:** Não.

**Origem:** issue [#6](https://github.com/CaioFaSoares/EnochDB/issues/6) e o mapa em [`../../../docs/arquitetura.md`](../../../docs/arquitetura.md). Vocabulário em [`../../../CONTEXT.md`](../../../CONTEXT.md).
