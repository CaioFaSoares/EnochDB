# Handover — 02_domain da s01-nucleo-enoch: ADRs, glossário e canon

> **Missão:** o dono confere se cada ADR descreve a dor e não só a solução, aprova a terminologia e fecha a etapa `02_domain`. Nada aqui implementa código.

## Origem e estado

As decisões D1 a D38 do grilling, aceitas pelo dono em 2026-10-15 ([`../../01_grilling/CONTEXT.md`](../../01_grilling/CONTEXT.md)), foram avaliadas uma a uma: o que tem trade-off arquitetural virou ADR; o que é escopo ou processo ficou no canon, por ponteiro; os termos já estavam no glossário.

- Decisões: [`../../01_grilling/handovers/decisoes.md`](../../01_grilling/handovers/decisoes.md)
- ADRs: [`../../../../adr/`](../../../../adr/) (0001 a 0010; o status de cada uma está no próprio arquivo)
- Glossário: [`../../../../../CONTEXT.md`](../../../../../CONTEXT.md)
- Canon: [`../../../../canon.md`](../../../../canon.md)
- Árvore de pastas: [`../../../../arquitetura.md`](../../../../arquitetura.md), issue [#1](https://github.com/CaioFaSoares/EnochDB/issues/1)

## Onde cada decisão passou a morar

| Decisão | Dor que a motivou (detalhe no Contexto da ADR) | Casa |
| --- | --- | --- |
| D6, D7, D8 | compilar Datalog para SQL deixaria a semântica da consulta ao dialeto de cada banco | [ADR-0001](../../../../adr/0001-avaliador-datalog-unico-em-elixir.md) |
| D16, D28 (D15 superada) | o presente não pode pagar pelo histórico, e retrair com `UPDATE` alterava linhas do log | [ADR-0002](../../../../adr/0002-modelo-acumulativo-log-estado-atual-historico.md) |
| D18, D21 (recuperação e supervisão) | no BEAM a estrutura persistente copia ao mudar de processo, e a escrita no ETS não é atômica | [ADR-0003](../../../../adr/0003-memory-ets-contador-base-e-recuperacao.md) |
| D14, D26, D27, D21 (funções de transação) | regras de escrita por banco divergiriam, e o BEAM não limita a caixa de entrada nem uma função em laço | [ADR-0004](../../../../adr/0004-transactor-unico-regras-de-escrita-e-admissao.md) |
| D19, D20, D21 (limites e telemetria) | o ETS não conta para `max_heap_size`: memória é o risco real de uma consulta ou escrita abusiva | [ADR-0005](../../../../adr/0005-salvaguardas-de-consulta-e-memoria.md) |
| D12, D13, D36, D37 | saldos exigem soma exata e a mesma ordem nos dois adaptadores; o `decimal` 2.4.1 tem avisos de segurança | [ADR-0006](../../../../adr/0006-decimal-inteiro-escalado-e-ordem-dos-tipos.md) |
| D24, D31, D32, D35 | banco por tenant em tempo de execução e `:memory:` por teste não cabem num módulo por banco; extensões precisam compor nomes sem colidir | [ADR-0007](../../../../adr/0007-schema-em-dados-api-funcional-e-registro-por-modulos.md) |
| D29, D34 | a sequência de subida original se contradizia, e deploys novos mudam o schema | [ADR-0008](../../../../adr/0008-subida-em-sete-passos-e-evolucao-do-schema.md) |
| D23, D38 (stack, nix, contêiner) | o e01 existe para provar o conceito, e o `beamPackages.elixir` padrão do nixpkgs (1.18.5) diverge do alvo | [ADR-0009](../../../../adr/0009-pacote-unico-sqlite-exqlite-e-toolchain.md) |
| D30 | materializar um saldo cria o risco de ele divergir dos fatos que o originam | [ADR-0010](../../../../adr/0010-valor-derivado-nunca-e-fonte-de-verdade.md); a opção C, que a D30 mandava para o e02, foi trazida para o e01 pelo dono (ver "Decisões do dono") |
| D1, D2, D5, D9, D10, D11, D17, D22 | escopo e processo, sem trade-off arquitetural próprio | [canon](../../../../canon.md), seção "Escopo e processo"; o texto fica em `decisoes.md` |
| D33 | escopo: o que do Tickety entra no e01 | `decisoes.md`; o [canon](../../../../canon.md) não repete a lista e a ADR-0001 aponta para ela |
| D25 | os termos Aplicação e Extensão colidiam com "aplicação OTP" | [glossário](../../../../../CONTEXT.md) e ADR-0007 |
| D38 (tracker, publicação) | processo, sem trade-off arquitetural próprio | [`../../../../agents/README.md`](../../../../agents/README.md) e [`arquitetura.md`](../../../../arquitetura.md) |
| D3, D4, D15 | superadas por D7, D6 e D16 | ADR-0001 e 0002 e a seção "Decisões superadas" do [canon](../../../../canon.md) |

## Termos

Nenhum termo novo entrou no glossário nesta etapa. Os termos que já estão em `CONTEXT.md` foram confirmados pelo dono: Aplicação e Extensão com os três tipos na D25, o restante do vocabulário no lote da D38. A aprovação final da terminologia é o gate do dono.

As ADRs usam o termo do glossário: "transactor" e "estado atual" (não "tabela atual"). O glossário agora só veta "writer" para o Transactor; o dono aceitou "escritor" (resposta de 2026-10-15).

## Situação atual

- Existem: 10 ADRs, `canon.md` com ponteiros, este handover, e as 14 pastas com `CONTEXT.md` da issue #1 (commit `6fefa18`, conforme o comentário da issue).
- Não foi rodado nenhum código nem teste; a etapa é só de documentos. Os fatos de versão e de NIF que as ADRs citam vêm de `decisoes.md`, não foram reverificados aqui.
- A issue #1 continua aberta: faltam a ratificação da árvore e o gate desta etapa.

## Decisões do dono nesta etapa (2026-10-15)

Respostas do dono às perguntas deste handover, dadas no chat. Ficam aqui e nas ADRs; `decisoes.md` não foi reaberto, exceto a linha 3 (estado), corrigida para o aceite.

- **Árvore e dicionário:** aprovados. `CONTEXT.md` deixou de vetar "escritor".
- **SQLite embutido** no contêiner do back, sem volume externo obrigatório, e o dono quer poder desabilitá-lo se possível. `arquitetura.md` e a ADR-0009 foram ajustados; a forma de desabilitar não foi escolhida.
- **Valor derivado agora:** a opção C (atributo declarado no schema e mantido pelo motor) entra no e01 e revoga em parte a D30. ADR-0010 e canon ajustados; a sprint sai na `03_spec`.
- **Divergência entre índice e transactor** (ADR-0004) e **conferência do último `t`** do SQLite (ADR-0002): a direção do dono está registrada nas ADRs; o mecanismo é proposta do agente, a confirmar na spec.
- **Iniciativas do agente:** aceitas, sem veto.
- **Decisão e fechamento pelo `/icm`:** o dono quer que o comando trate o recibo, o status das ADRs e o fechamento. Modo `decidir` criado em `.omp/commands/icm.md`.

## Pontos para o dono conferir

- **A dor, não só a solução:** a seção "Contexto" de cada ADR. A ADR-0010 foi a mais frágil e recebeu uma dor própria do Enoch (o e03 depende de saldos, D9, e a materialização sem regra viraria segunda fonte de verdade); o restante do contexto se apoia no Tickety e no chat.
- **Iniciativas do agente nas ADRs**, aceitas junto com o conjunto em 2026-10-15 e marcadas como tais no texto: mitigação da fronteira `Storage` (ADR-0001), métrica determinística de linhas lidas (ADR-0002), igualdade entre tipos não numéricos sem erro (ADR-0006), atribuição de entregas das D34 e D35 às sprints (ADR-0007 e 0008), versão do layout como método do contrato (ADR-0008), piso `~> 1.20`, comandos do flake e `Dockerfile` em dois estágios (ADR-0009).
- **Pendências que ficam para a spec** (registradas nas ADRs, não decididas): vazamento do contador de admissão por chamador que morre, contador negativo se o incremento anteceder o `init` e desfazer o incremento de um chamador rejeitado (ADR-0004, as duas últimas como inferência); percentual do limite brando (ADR-0005); unidade de `:instant` (ADR-0006); lista de alterações compatíveis do instalador, forma da versão do layout e destino do ensaio da instalação (ADR-0008); forma de desabilitar o SQLite (ADR-0009); sprint e corte da opção C, e se `verify_derived` vira obrigatório na subida (ADR-0010); o que "valer o valor mais novo" significa numa divergência entre índice e transactor, e como validar o `t` correto no SQLite (ADR-0004 e ADR-0002).
- **Não verificado, herdado do grilling:** NIF pré-compilado em Alpine, `mix release` na imagem enxuta, WAL em arquivo sob musl, OTP 28 e Linux (ADR-0009).

## Primeiros passos

1. Se o texto está aceito: `/icm decidir aceito`. O comando registra a decisão sobre o recibo vigente, troca o status das ADRs e, com a sua confirmação, a ficha.
2. Se quiser ajustar algo: edite, rode `/icm` (grava o recibo novo) e então `/icm decidir <decisão>` sobre esse recibo.
3. A issue #1 fecha com você, depois de ratificar a árvore.
