# 03_spec — especificar o resultado

## Objetivo

Converter decisões aprovadas em comportamento verificável, sem reabrir a entrevista nem acrescentar escopo por suposição.

## Entradas

- `01_grilling/handovers/decisoes.md` e `02_domain/handovers/adrs.md` da sprint atual.
- Glossário, canon e ADRs locais.
- Tracker somente se houver uma decisão aprovada que o identifique.

## Processo

1. Escreva user stories ou casos de uso e critérios de aceite observáveis. Toda decisão fechada no grilling aparece como requisito ou como fora de escopo.
2. Registre os seams de verificação e prefira os existentes aos novos.
3. Se já houver código, faça o mapeamento opcional entre cada requisito e seus pontos de implementação; guarde-o em `handovers/spec-tecnica.md`.
4. Mantenha o corpo da spec nesta pasta de handover enquanto o tracker não estiver escolhido. Depois da escolha, atualize a spec no local que ela definir e mantenha aqui apenas o ponteiro e os critérios que a execução precisa carregar.
5. Atualize canon, ADRs ou glossário se a especificação revelar uma decisão nova; não trate uma hipótese como autorização.

## Saída e gate humano

Saída: `docs/_sprints/{sprint}/03_spec/handovers/spec.md` e, quando houver base de código, `spec-tecnica.md`. O dono verifica cobertura de todas as decisões, critérios testáveis e limites de escopo.

## Quando não se aplica

Pode ser `nao-aplicavel` quando uma spec completa e aprovada já é a entrada do trabalho. A ficha aponta essa spec; não crie uma segunda.
