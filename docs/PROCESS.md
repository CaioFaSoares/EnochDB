# Processo documental do EnochDB

Este arquivo e os contratos em `docs/NN_step/` são a definição local do processo. O EnochDB não depende de documentação ou executáveis de outro repositório para usar esta estrutura.

O fluxo é: **interrogar → registrar decisões → especificar → fatiar → implementar → revisar → passar o contexto adiante**. Uma sprint é uma execução completa dessas sete etapas. A ordem numérica e a árvore de pastas carregam a sequência; as fichas e handovers registram o que aconteceu.

## Etapas e gates

| Etapa | Trabalho | Saída principal | Gate humano |
| --- | --- | --- | --- |
| `01_grilling` | esclarecer a necessidade até separar decisões, descartes e perguntas abertas | `handovers/decisoes.md` | o dono confirma as decisões; nenhuma hipótese vira decisão por inferência |
| `02_domain` | registrar decisões arquiteturais e termos de domínio | ADRs, glossário e `handovers/adrs.md` | revisar o contexto e as consequências de cada ADR e aprovar os termos |
| `03_spec` | converter decisões em especificação verificável | `handovers/spec.md` e, quando útil, `spec-tecnica.md` | conferir que todas as decisões aparecem como requisito ou fora de escopo |
| `04_tickets` | dividir a especificação em fatias verticais ordenadas por dependência | `handovers/tickets.md` | aprovar granularidade e bloqueios antes de publicar trabalho |
| `05_implement` | executar uma fatia autorizada por vez, test-first | `handovers/implementacao.md` | suíte relevante verde e caminho de uso exercitado |
| `06_review` | comparar a entrega com a spec e os padrões documentados | `handovers/revisao.md` e `handovers/pr.md` | resolver ou registrar cada achado antes de abrir PR |
| `07_handoff` | deixar o próximo trabalho compreensível sem memória da sessão | `handovers/handoff.md` | leitura sem contexto deve bastar para começar |

**Regra de avanço:** uma pessoa lê e aceita o handover da etapa anterior antes de começar a seguinte. Se o gate não aconteceu, a ficha não declara a etapa fechada.

## Casas da informação

- `../CONTEXT.md`: glossário aprovado do domínio.
- `canon.md`: estado atual do plano e decisões vigentes, com histórico superado anotado.
- `adr/`: uma decisão arquitetural por arquivo.
- `agents/`: orientação local para agentes e para o tracker quando ele for escolhido.
- `_templates/`: modelos próprios desta documentação.
- `_sprints/{sprint}/`: inputs, ficha e handovers de cada execução.
- `_index/sprints.md`: catálogo de conveniência; não substitui as fichas.

Uma decisão aprovada atualiza o canon; um trade-off arquitetural relevante recebe ADR; um termo de domínio aprovado entra no glossário. Handovers apontam para essas fontes em vez de manter cópias. O texto em `canon/chat.md` é contexto histórico bruto, não decisão vigente.

## Fichas, estado e etapas não aplicáveis

Cada etapa de uma sprint tem `CONTEXT.md`, `inputs/` e `handovers/`. A ficha registra somente status, skills ou ferramentas realmente usadas, resultado e links para os handovers; o contrato estável da etapa fica em `docs/NN_step/CONTEXT.md`.

Estados permitidos: `vazio`, `em-curso`, `fechado` e `nao-aplicavel`. O estado de uma etapa fechada precisa de evidência na ficha ou de `handovers/.closed`. Pasta vazia não significa que a etapa não se aplica.

Só `01_grilling`, `03_spec` e `04_tickets` podem ser marcadas `nao-aplicavel`, sempre com motivo e com a fonte que substituiu a etapa. As demais etapas não são eliminadas para encurtar o fluxo.

## Abrir uma sprint

Use um identificador `sNN-slug`. No diretório raiz do EnochDB, crie a árvore a partir do modelo local:

```sh
SPRINT=s01-exemplo
for step in 01_grilling 02_domain 03_spec 04_tickets 05_implement 06_review 07_handoff; do
  mkdir -p "docs/_sprints/$SPRINT/$step/inputs" "docs/_sprints/$SPRINT/$step/handovers"
  cp docs/_templates/sprint-CONTEXT.md "docs/_sprints/$SPRINT/$step/CONTEXT.md"
done
```

Edite cada ficha para substituir o identificador, etapa e data; não cole nela o contrato. Registre a sprint em `_index/sprints.md` e coloque o material bruto novo apenas em `01_grilling/inputs/`. Para material que já tem casa, registre o caminho em vez de copiá-lo.

## Tracker e publicação

O tracker do EnochDB ainda não foi escolhido. Até essa decisão ser registrada, as etapas `03_spec` e `04_tickets` podem preparar seus handovers, mas não devem publicar issues nem inventar um fluxo externo. A convenção de publicação entra em `agents/` depois da escolha.
