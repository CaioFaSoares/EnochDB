# Guia de documentação — EnochDB

## Começar

1. Leia [`PROCESS.md`](PROCESS.md), o glossário [`../CONTEXT.md`](../CONTEXT.md) e o canon [`canon.md`](canon.md).
2. Leia `canon/chat.md` apenas como contexto histórico. Ele contém hipóteses e alternativas, não decisões aprovadas.
3. Abra uma sprint seguindo a seção **Abrir uma sprint** de `PROCESS.md`. Os contratos locais em `docs/NN_step/CONTEXT.md` definem cada etapa; a ficha em `_sprints/{sprint}/NN_step/CONTEXT.md` registra o resultado daquela execução.
4. Avance uma etapa por vez e pare para o human check descrito no contrato. Não marque etapa como fechada sem evidência.

## Conduzir uma sprint

- **01 — grilling:** esclareça a necessidade com o dono. Registre decisões fechadas, itens descartados com motivo e perguntas abertas com o que falta para respondê-las.
- **02 — domain:** dê uma casa permanente às decisões aprovadas. Registre trade-offs em ADRs e termos de domínio no glossário.
- **03 — spec:** escreva critérios verificáveis a partir do que já foi decidido. Não reabra a entrevista; se falta uma decisão, volte ao grilling. O tracker ainda não foi escolhido, então não publique issues.
- **04 — tickets:** quando houver tracker aprovado, fatie a spec em caminhos verticais completos e torne bloqueios explícitos. Antes disso, registre a proposta no handover e aguarde a escolha do tracker.
- **05 — implement:** trabalhe em uma fatia autorizada por vez. Teste antes da mudança e exercite o caminho no programa real.
- **06 — review:** compare diff, critérios da spec e contratos locais. Resolva achados ou registre seu destino antes de abrir PR.
- **07 — handoff:** aponte para decisões, tickets, commits e evidências pelas fontes originais. Registre riscos e próximos passos sem depender da memória do autor.

## Manter as fontes coerentes

Quando uma etapa revelar uma decisão técnica ou mudança de escopo, atualize `canon.md`; formalize trade-offs relevantes em `adr/`; acrescente ao `CONTEXT.md` apenas termos aprovados. Não copie o conteúdo de uma dessas fontes para outra. O índice de sprints é derivado das fichas e não é fonte de status.
