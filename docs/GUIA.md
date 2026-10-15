# Guia de documentação — EnochDB

## Começar

1. Leia [`PROCESS.md`](PROCESS.md), o glossário [`../CONTEXT.md`](../CONTEXT.md) e o canon [`canon.md`](canon.md).
2. Leia `canon/chat.md` apenas como contexto histórico. Ele contém hipóteses e alternativas, não decisões aprovadas.
3. Abra um épico e uma sprint seguindo as seções **Abrir um épico** e **Abrir uma sprint** de `PROCESS.md`. A ficha em `_sprints/{sprint}/CONTEXT.md` diz a que épico a sprint pertence; os contratos em `docs/NN_step/CONTEXT.md` definem cada etapa, e a ficha em `_sprints/{sprint}/NN_step/CONTEXT.md` registra o resultado daquela execução.
4. Avance uma etapa por vez e pare para o human check descrito no contrato. Não marque etapa como fechada sem evidência.

## Conduzir uma sprint

- **01 — grilling:** esclareça a necessidade com o dono. Registre decisões fechadas, itens descartados com motivo e perguntas abertas com o que falta para respondê-las.
- **02 — domain:** dê uma casa permanente às decisões aprovadas. Registre trade-offs em ADRs e termos de domínio no glossário.
- **03 — spec:** escreva critérios verificáveis a partir do que já foi decidido. Não reabra a entrevista; se falta uma decisão, volte ao grilling. O tracker ainda não foi escolhido, então não publique issues.
- **04 — tickets:** quando houver tracker aprovado, fatie a spec em caminhos verticais completos e torne bloqueios explícitos. Antes disso, registre a proposta no handover e aguarde a escolha do tracker.
- **05 — implement:** trabalhe em uma fatia autorizada por vez. Teste antes da mudança e exercite o caminho no programa real.
- **06 — review:** compare diff, critérios da spec e contratos locais. Resolva achados ou registre seu destino antes de abrir PR.
- **07 — handoff:** aponte para decisões, tickets, commits e evidências pelas fontes originais. Registre riscos e próximos passos sem depender da memória do autor.

## Acompanhar

- `_index/estado.sh` deriva o estado de épicos e sprints a partir do frontmatter; é somente leitura.
- `_index/sprints.md` e `_index/epicos.md` são catálogos de conveniência, não fonte de estado.
- `epicos/` guarda as frentes duráveis; a ficha da sprint aponta para a sua com `epico:`.

## Manter as fontes coerentes

Quando uma etapa revelar uma decisão técnica ou mudança de escopo, atualize `canon.md`; formalize trade-offs relevantes em `adr/`; acrescente ao `CONTEXT.md` apenas termos aprovados. Não copie o conteúdo de uma dessas fontes para outra. Um fato — a etapa tem este status, a sprint pertence a este épico — mora em um arquivo só; os índices em `_index/` são derivados e não são fonte de estado.
