# Tickets — s01 do e01 `nucleo-enoch` (sprint s01-nucleo-enoch, etapa 04_tickets)

> **Missão:** as fatias da s01 foram aprovadas pelo dono e publicadas no GitHub em 2026-10-15. Os rótulos `F1` a `F9` abaixo correspondem às issues da seção "Issues publicadas".

## Origem

- Spec aceita: [`../../03_spec/handovers/spec.md`](../../03_spec/handovers/spec.md). Cada ticket cita os requisitos (R#) e as decisões (D#) por número; o texto da spec não é copiado.
- Escopo da s01: a tabela "Escopo por sprint" e os campos *Sprint* da spec. O que a spec atribui a s02 a s05 está em "Fora desta sprint".
- Tracker: GitHub Issues de `CaioFaSoares/EnochDB` ([`../../../../agents/README.md`](../../../../agents/README.md)). Sem convenção de labels: valem as padrão.
- Árvore de módulos: [`../../../../arquitetura.md`](../../../../arquitetura.md). Fatiamento proposto pelo papel `30-ticketing-slicer`, conferido contra a spec.

## Issues publicadas

Lista que o `/icm implement` lê. A seção `Dependências` de cada issue cita os bloqueadores por `#N`.

- F1: #2
- F2: #3
- F3: #4
- F4: #5
- F5: #6
- F6: #7
- F7: #8
- F8: #9
- F9: #10

## Ordem e paralelismo

1. F1.
2. F2 em paralelo com F9.
3. F3 em paralelo com F4.
4. F5, F6 e F8 em paralelo (F6 espera F3 e F4).
5. F7.

Posse de arquivos, para o coordenador da implementação: `memory.ex` passa por F2, F3 e F6; `storage.ex` por F2, F3 e F7; `transactor.ex`, `instance/supervisor.ex` e `enoch.ex` por F4, F5 e F7; `owner.ex` por F4 e F6. Pares paralelos com arquivos disjuntos: F3 e F4; F5 e F6 (F6 não toca `transactor.ex` nem `supervisor.ex`); F8 e F9 com qualquer outra.

## Fatias

### F1. Esqueleto do pacote: `mix test` roda

**Requisitos:** R33 (D23, D37, D38). **Arquivos:** `mix.exs`, `mix.lock`, `.formatter.exs`, `config/config.exs`, `lib/enoch.ex` (só `@moduledoc`), `lib/enoch/application.ex` (supervisor vazio), `test/test_helper.exs`, `test/enoch/application_test.exs`.

**Escopo:** pacote único `enoch` com app OTP `:enoch`, piso `elixir: "~> 1.20"`, dependências `decimal ~> 3.2`, `telemetry ~> 1.0`, `stream_data ~> 1.0` só em teste e `exqlite` opcional (R34). Sem lógica de domínio.

**Critérios de aceite**
- [ ] `mix deps.get`, `mix compile` e `mix test` passam com Elixir 1.20.4 e OTP 29.
- [ ] `mix hex.audit` não acusa avisos.
- [ ] Um teste de fumaça sobe o app `:enoch`.

**Dependências:** nenhuma.

### F2. Contrato `Enoch.Storage` e `Memory`: gravar e varrer pelo histórico

**Requisitos:** R1, R2 (só `Memory`), R4 (estrutura e escritor), R8 (conferência), R16 (só a opção `max_memory`), R25 (behaviour e suíte) (D6, D7, D16, D18, D20, D24). **Arquivos:** `lib/enoch/storage.ex`, `lib/enoch/storage/contract_case.ex`, `lib/enoch/adapters/memory.ex`, `lib/enoch/db.ex`, `test/support/*`, `test/enoch/storage/*`, `test/enoch/adapters/memory_test.exs`.

**Escopo:** o behaviour com varreduras dos índices e pushdown por `a`, `v` e `t`, sem `compile/2`; a suíte `use Enoch.Storage.ContractCase`; o `Memory` com duas tabelas ETS e o contador em `:atomics`, com o escritor na ordem da D18; o banco como valor `{referências, basis_t}`. `Memory.open/1` cria as tabelas no processo que a chama, sem presumir dono, para F3 e F4 correrem em paralelo.

**Critérios de aceite**
- [ ] Nenhum callback recebe uma consulta Datalog e não existe `compile/2`.
- [ ] As varreduras EAVT, AEVT, AVET e VAET com pushdown por `a`, `v` e `t` passam na suíte de contrato.
- [ ] Afirmar, retrair e reafirmar o mesmo `(e, a, v)` deixa três linhas no histórico e um datom no estado atual; o estado atual reconstruído do histórico é idêntico ao gravado.
- [ ] O escritor segue a ordem da D18: contador para `2t+1`, histórico, atual, contador para `2t+2`.
- [ ] Teste obrigatório (D18): banco de base `L` com a transação `L+1` completa antes da varredura lê consistente com `L`.
- [ ] Um adaptador de teste fora de `lib/enoch/adapters` roda `use Enoch.Storage.ContractCase`.
- [ ] As quatro varreduras do Anexo A da spec (EAVT, AEVT, AVET e VAET, no presente e no passado) mapeiam para os callbacks do contrato.
- [ ] O `Memory` exige a opção `max_memory`, aceita `:infinity` e não sobe sem ela (D20); a cota e o alerta são da s05.

**Dependências:** F1.

### F3. `Memory`: presente pelo estado atual, leitura concorrente e contador de linhas lidas

**Requisitos:** R4 (leitor), R6 (D17 critério 3, D18). **Arquivos:** `lib/enoch/adapters/memory.ex`, `lib/enoch/storage.ex` (callback do contador de linhas), `ContractCase`.

**Critérios de aceite**
- [ ] O leitor só usa o estado atual se o contador valer `2b` antes e depois da varredura; senão refaz a varredura pelo histórico na mesma base, sem repetir em laço.
- [ ] Um teste de leitura concorrente com escrita contínua termina e é consistente com a base.
- [ ] O adaptador expõe as linhas lidas por varredura.
- [ ] Uma consulta ao presente lê o mesmo número de linhas antes e depois de N retrações.

**Dependências:** F2 (mesmo `memory.ex`; usa o escritor e o fallback pelo histórico).

### F4. Instância mínima: `Enoch.start_link`, `transact` com `add` e `retract` crus e `db`

**Requisitos:** R11 (só o cru), R30 (núcleo e instâncias) (D32, D18). **Arquivos:** `lib/enoch.ex`, `lib/enoch/application.ex`, `lib/enoch/instance/supervisor.ex`, `lib/enoch/instance/owner.ex`, `lib/enoch/transactor.ex`.

**Escopo:** a instância sobe uma árvore própria com o processo dono das tabelas e o transactor. A estratégia do supervisor mantém o dono vivo quando o transactor cai (F6 depende disso).

**Critérios de aceite**
- [ ] `Enoch.start_link(name:, adapter:)` sobe a árvore de supervisão da instância.
- [ ] `Enoch.transact(nome, [add, retract])` grava e `Enoch.db(nome)` devolve o banco como valor com `basis_t`.
- [ ] Duas instâncias com nomes diferentes convivem no mesmo nó sem compartilhar estado.
- [ ] `:memory:` por teste não exige módulo próprio.

**Dependências:** F2. Não precisa de F3.

### F5. Admissão limitada, fechada e aberta

**Requisitos:** R13 (D27, D34). **Arquivos:** `lib/enoch/instance/admission.ex`, `lib/enoch/transactor.ex`, `lib/enoch.ex`, `lib/enoch/instance/supervisor.ex`.

**Critérios de aceite**
- [ ] Acima do limite o chamador recebe rejeição explícita antes de a mensagem entrar na caixa; o chamador rejeitado desfaz o próprio incremento.
- [ ] Com a admissão fechada, uma escrita externa é rejeitada.
- [ ] Depois de matar o transactor, o contador de admissão volta a zero (o `init` zera).
- [ ] Matar um chamador entre incrementar e enviar deixa o contador igual à caixa real depois da reconciliação por `message_queue_len`.

**Dependências:** F4 (o transactor, `enoch.ex` e o supervisor já existem).

### F6. Recuperação após queda do transactor no meio da escrita

**Requisitos:** R5 (D21, D18). **Arquivos:** `lib/enoch/adapters/memory.ex`, `lib/enoch/instance/owner.ex`, `test/enoch/adapters/memory_recovery_test.exs`.

**Critérios de aceite**
- [ ] O teste "queda no meio da escrita", com leitor em curso durante a recuperação, passa no `Memory`.
- [ ] Após a queda o contador fica em `2t+1`, as linhas órfãs `tx = t+1` são apagadas, o estado atual é reconstruído do histórico até `t` e o contador é publicado em `2(t+1)`.
- [ ] A transação seguinte é `t+2`.
- [ ] As tabelas sobrevivem à queda do transactor (`heir`).

**Dependências:** F3 (o leitor em curso depende do leitor por contador) e F4 (transactor e dono para derrubar).

### F7. Subida (passos 1, 2, 3 e 7), mecanismo do passo 4 e telemetria da subida

**Requisitos:** R31, R24 (mecanismo), R17 (só a subida), R13 (estados) (D34, D35). **Arquivos:** `lib/enoch/instance/boot.ex`, `lib/enoch/storage.ex` (callback da versão do layout), `lib/enoch/adapters/memory.ex`, `lib/enoch/telemetry.ex`, `lib/enoch/instance/supervisor.ex`, `lib/enoch.ex`, `lib/enoch/tx/function.ex` (só o behaviour).

**Escopo:** o passo 5 (schema), o passo 6 (migrações) e a versão do layout no SQLite não entram: são da s02, s05 e s04. O registro genérico de funções e regras fica em `boot.ex` até haver `schema/registry.ex` (s02) e `query/rules.ex` (s03).

**Critérios de aceite**
- [ ] Um layout mais novo impede a subida e a admissão continua fechada.
- [ ] Um estado atual adulterado é reconstruído na subida (passo 2).
- [ ] Dois módulos que registram o mesmo nome de função ou de regra impedem a subida.
- [ ] A admissão abre no passo 7 e um evento `:telemetry` com a base é capturado.
- [ ] Uma instância sobe com módulos de schema, de funções e de regras definidos fora do pacote.

**Dependências:** F4 (supervisor e `start_link`), F5 (estados da admissão) e F6 (o passo 2 chama a recuperação).

### F8. Esqueleto de `use Enoch.Repo`

**Requisitos:** R30 (resto) (D32). **Arquivos:** `lib/enoch/repo.ex`, `test/enoch/repo_test.exs`.

**Critérios de aceite**
- [ ] Um `Enoch.Repo` e a chamada funcional por nome dão o mesmo resultado em `transact` e `db`.

**Dependências:** F4 (só chama a API por nome).

### F9. Flake e comandos do projeto

**Requisitos:** R34 (parte da s01) (D38). **Arquivos:** `flake.nix`.

**Critérios de aceite**
- [ ] O flake fixa `beam.packages.erlang_29.elixir_1_20` e o `devShell` continua.
- [ ] `nix run .#test`, `nix run .#estado` e `nix flake check` rodam.

**Dependências:** F1 (`.#test` precisa de `mix.exs`). O `Dockerfile` fica na s05.

## Cobertura dos requisitos da s01

| Requisito | Fatia |
| --- | --- |
| R1 | F2 |
| R2 (só `Memory`) | F2 |
| R4 | F2 (estrutura e escritor), F3 (leitor) |
| R5 | F6 (recuperação), F5 (contador de admissão volta a zero) |
| R6 | F3 |
| R8 | F2 (conferência do Anexo A) |
| R11 (só `add` e `retract` crus) | F4 |
| R13 (mecanismo e estados) | F5, F7 |
| R16 (só a opção `max_memory`) | F2 |
| R17 (só a subida) | F7 (o contador de linhas vem em F3) |
| R24 (mecanismo) | F7 |
| R25 (behaviour e suíte) | F2 |
| R30 (núcleo, `Repo`, listas de módulos) | F4, F8, F7 |
| R31 (passos 1, 2, 3, 7 e mecanismo do 4) | F7 |
| R33 | F1 |
| R34 (flake) | F9 |
| R35, R36 | transversais: todas as fatias usam o vocabulário do glossário e cada issue aponta a spec pelo caminho |

## Fora desta sprint

A spec cobre o e01 inteiro; estas fatias são só as da s01. Ficam para os tickets das sprints seguintes: s02 (R9, R10, R11 restante, R12, R18, R19, R21 a R24 restantes, R25 metadados), s03 (R3, R15, R20, R26 a R28, R29 parcial), s04 (R2 e R7 do SQLite, R14, R31 versão no SQLite, R32), s05 (R12 limites, R14, R16, R17 restante, R23, R29 manutenção automática, R34 `Dockerfile`, R37 item 2).

## Decisões do dono antes de publicar (2026-10-15)

- **Granularidade e bloqueios:** as 9 fatias foram aprovadas, com publicação no GitHub.
- **R8:** o dono pediu as quatro consultas; o Anexo A da spec agora traz as quatro varreduras (EAVT, AEVT, AVET, VAET) no presente e no passado, e a spec tem recibo novo.
- **`max_memory` na s01:** o dono aprovou que o `Memory` exija a opção `max_memory` já na s01 (F2), para a D20 valer desde o início.
- **Padrões adotados pelo agente, sem objeção do dono e a confirmar:** o contador de linhas lidas fica no contrato (F3) e o evento `rows_read` fica para a s05; `{:exqlite, "~> 0.42", optional: true}` (a D23 testou a 0.42.0); o registro genérico de funções e regras (passo 4) fica em `boot.ex` (F7) até haver arquivo próprio. O dono não foi perguntado sobre esses três pontos.
- **Publicação:** cada issue segue o corpo das fatias acima, com a seção `Dependências` citando `#N`; os números entram aqui depois de publicar.

