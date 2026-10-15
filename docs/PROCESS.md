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
- `epicos/`: uma frente durável por arquivo; agrupa sprints rumo a um resultado observável.
- `agents/`: orientação local para agentes e para o tracker quando ele for escolhido.
- `_templates/`: modelos próprios desta documentação.
- `_sprints/{sprint}/`: ficha da sprint, inputs e handovers de cada execução.
- `_index/`: catálogos de conveniência (`sprints.md`, `epicos.md`) e `estado.sh`, que deriva o estado. Não substituem as fichas.

Uma decisão aprovada atualiza o canon; um trade-off arquitetural relevante recebe ADR; um termo de domínio aprovado entra no glossário. Handovers apontam para essas fontes em vez de manter cópias. O texto em `canon/chat.md` é contexto histórico bruto, não decisão vigente.

## Épicos, sprints e uma casa por fato

Um **épico** (`epicos/eNN-slug.md`) é a frente durável: guarda o objetivo de produto, o resultado observável e o próprio `status` (`aberto`, `concluido`, `descartado`). Uma **sprint** (`_sprints/sNN-slug/`) é uma execução do fluxo de sete etapas.

Cada fato tem uma casa só:

- a sprint declara a que épico pertence, no `epico:` da sua ficha (`_sprints/{sprint}/CONTEXT.md`);
- o estado de uma etapa vive no `status:` da ficha da etapa;
- o estado de uma sprint é **derivado** das fichas das suas etapas; não se declara;
- a lista de sprints de um épico é **derivada** do `epico:` das fichas de sprint; o épico não a repete.

Ninguém escreve o estado de outro arquivo. Para ver o conjunto, rode `sh docs/_index/estado.sh`.

## Fichas, estado e etapas não aplicáveis

Cada etapa de uma sprint tem `CONTEXT.md`, `inputs/` e `handovers/`. A ficha registra somente status, skills ou ferramentas realmente usadas, resultado e links para os handovers; o contrato estável da etapa fica em `docs/NN_step/CONTEXT.md`.

Estados permitidos: `vazio`, `em-curso`, `fechado` e `nao-aplicavel`. O estado de uma etapa fechada precisa de evidência na ficha ou de `handovers/.closed`. Pasta vazia não significa que a etapa não se aplica.

Só `01_grilling`, `03_spec` e `04_tickets` podem ser marcadas `nao-aplicavel`, sempre com motivo e com a fonte que substituiu a etapa. As demais etapas não são eliminadas para encurtar o fluxo.

## Abrir um épico

Use um identificador `eNN-slug`:

```sh
mkdir -p docs/epicos
cp docs/_templates/epico.md docs/epicos/e01-slug.md
```

Preencha objetivo, resultado observável, fora de escopo e `status`, e registre o épico em `_index/epicos.md`. As sprints apontam para ele com `epico: e01-slug`; não liste as sprints dentro do épico.

## Abrir uma sprint

Use um identificador `sNN-slug`. No diretório raiz do EnochDB, crie a árvore a partir dos modelos locais:

```sh
SPRINT=s01-exemplo
mkdir -p "docs/_sprints/$SPRINT"
cp docs/_templates/sprint.md "docs/_sprints/$SPRINT/CONTEXT.md"
for step in 01_grilling 02_domain 03_spec 04_tickets 05_implement 06_review 07_handoff; do
  mkdir -p "docs/_sprints/$SPRINT/$step/inputs" "docs/_sprints/$SPRINT/$step/handovers"
  cp docs/_templates/sprint-CONTEXT.md "docs/_sprints/$SPRINT/$step/CONTEXT.md"
done
```

Preencha a ficha da sprint (identificador, título, `epico:` e data) e cada ficha de etapa (identificador, etapa e data); não cole o contrato nelas. Registre a sprint em `_index/sprints.md` e coloque o material bruto novo apenas em `01_grilling/inputs/`. Para material que já tem casa, registre o caminho em vez de copiá-lo.

## Tracker e publicação

O tracker é escolhido e a convenção de uso está em [`agents/README.md`](agents/README.md). As etapas `03_spec` e `04_tickets` preparam seus handovers e só publicam issues depois da aprovação humana descrita no contrato de cada etapa.
