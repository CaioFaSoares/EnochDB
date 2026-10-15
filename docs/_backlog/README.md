# _backlog — o que apareceu e ainda não tem sprint

Cada arquivo `Bnn-slug.md` é uma dúvida ou ideia explorada (normalmente no `/icm duck`) e que ainda não foi posicionada. Não é fonte de decisão: decisão mora no `canon.md`, nos ADRs e no `decisoes.md` de uma sprint.

- **Onde mora é o status.** Em `_backlog/` está sem sprint. Posicionar é mover o arquivo (`git mv`) para `docs/_sprints/<sprint>/01_grilling/inputs/` de uma sprint ainda não iniciada; ato do dono. Nenhum arquivo declara a sprint de destino.
- **Âncora ou ideia.** Fato tem âncora `arquivo:linha` conferida pelo `docs/_index/icm-duck.mjs`. Sem âncora, o item leva `sem_ancora: true` e vale como ideia.
- **`epico_sugerido`** é consultivo (Jev) e pode ser `—`. O épico real é o `epico:` da ficha da sprint que o receber.
- O estado derivado aparece em `sh docs/_index/estado.sh`. Mecanismo: [`../agents/jev.md`](../agents/jev.md).
