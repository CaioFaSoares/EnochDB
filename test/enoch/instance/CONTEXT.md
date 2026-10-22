# test/enoch/instance/

**Propósito:** Os testes da instância: a admissão limitada — o limite, os estados fechado e aberto, a queda do transactor, a reconciliação do contador e a concorrência (`admission_test.exs`) —, a subida em sete passos (`boot_test.exs`) e o dono das tabelas (`owner_test.exs`).

**Decisões:** D27 (contador em `:atomics`, rejeição antes da caixa, vazamento do contador), D34 (admissão fechada na subida e aberta no passo 7), D21 e D18 (dono das tabelas, recuperação). Texto em [`../../../docs/_sprints/s01-nucleo-enoch/01_grilling/handovers/decisoes.md`](../../../docs/_sprints/s01-nucleo-enoch/01_grilling/handovers/decisoes.md).

**Sprint:** s01: admissão limitada, os dois estados, os passos 1, 2, 3, 4 (mecanismo) e 7 da subida, e a queda do dono. s02: os passos 5 e o registro de funções. s05: a telemetria da admissão e o passo 6.

**Fronteira:** Não é a suíte de contrato do adaptador (essa é `../storage/`) nem o teste da recuperação da escrita (esse é `../adapters/memory_recovery_test.exs`, da ADR-0003); aqui o que se mede é a contabilidade da admissão e o caminho de escrita que a usa.

**Ponto de extensão:** Não.

**Origem:** issue [#6](https://github.com/CaioFaSoares/EnochDB/issues/6) e o mapa em [`../../../docs/arquitetura.md`](../../../docs/arquitetura.md). Vocabulário em [`../../../CONTEXT.md`](../../../CONTEXT.md).
