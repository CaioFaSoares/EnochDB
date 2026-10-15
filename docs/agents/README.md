# Convenções para agentes — EnochDB

Antes de explorar ou alterar o projeto, leia [`../../CONTEXT.md`](../../CONTEXT.md), [`../canon.md`](../canon.md) e os ADRs em [`../adr/`](../adr/) que tocam a área. Se um arquivo ainda não existir ou estiver sem termos, siga com os fatos disponíveis; não invente uma decisão só para preencher a estrutura.

Use o vocabulário aprovado no glossário em nomes, specs e testes. Se um termo necessário estiver ausente, anote a lacuna para a etapa de domínio. Se a mudança contradisser um ADR, exponha o conflito e peça uma decisão explícita; não reescreva o histórico em silêncio.

## Épicos e sprints

O trabalho é agrupado por épicos em [`../epicos/`](../epicos/); cada sprint aponta para o seu no campo `epico:` da ficha em `docs/_sprints/{sprint}/CONTEXT.md`. O estado derivado sai de `sh docs/_index/estado.sh`; não replique status de épico ou de sprint em outro arquivo.

## Julgamento (Jev)

Antes de declarar uma etapa pronta, e antes de implementar quando houver mais de um caminho, consulte os gates de julgamento: [`jev.md`](jev.md). O Jev é consultivo; achado vira leitura do artefato, e fechar etapa continua sendo do dono. Perguntas e limiares moram só em [`jev-gates.json`](jev-gates.json).

## Tracker

O tracker é o GitHub Issues do repositório `CaioFaSoares/EnochDB` (decisão D38 em [`../_sprints/s01-nucleo-enoch/01_grilling/handovers/decisoes.md`](../_sprints/s01-nucleo-enoch/01_grilling/handovers/decisoes.md)). As etapas `03_spec` e `04_tickets` publicam lá. Uma issue aponta para os documentos pelo caminho em vez de copiar o conteúdo, e a arquitetura de pastas está em [`../arquitetura.md`](../arquitetura.md). Convenção de labels e de dependências entre issues ainda não foi decidida: não invente uma; as labels padrão do GitHub bastam por enquanto.
