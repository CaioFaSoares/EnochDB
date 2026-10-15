# Épicos — EnochDB

Um épico é uma frente durável com um objetivo de produto e um resultado observável. Ele agrupa uma ou
mais sprints que perseguem esse objetivo e aponta para onde as decisões vivem; não descreve passo a passo.

## Uma casa por fato

- A **sprint** declara a que épico pertence, no campo `epico:` da ficha em `_sprints/{sprint}/CONTEXT.md`.
- O **épico** declara o próprio estado, no `status:` do seu frontmatter.
- A lista de sprints de um épico é **derivada** do `epico:` das fichas de sprint; não é copiada para o épico.
- O estado de uma sprint é **derivado** das fichas das suas sete etapas; o épico não repete status de sprint.

Nenhum arquivo escreve o estado de outro. Para ver o conjunto, rode `sh ../_index/estado.sh`.

## Criar um épico

```sh
mkdir -p docs/epicos
cp docs/_templates/epico.md docs/epicos/e01-slug.md
```

Preencha objetivo, resultado observável, fora de escopo e status, e registre o épico em
`../_index/epicos.md`. Depois aponte as sprints para ele com `epico: e01-slug`.

## Estados

- `aberto` — em planejamento ou com sprint em andamento.
- `concluido` — resultado observável atingido e aceito pelo dono.
- `descartado` — abandonado, com o motivo registrado no corpo; o arquivo não é apagado.
