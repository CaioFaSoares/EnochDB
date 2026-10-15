# Arquitetura de pastas do pacote `enoch`

Mapa das pastas de código do e01. As 14 pastas existem, cada uma só com um `CONTEXT.md` (issue [#1](https://github.com/CaioFaSoares/EnochDB/issues/1)); os arquivos `.ex`, `mix.exs`, `flake.nix` e `Dockerfile` da árvore **ainda não existem** e nascem nas sprints do e01 (D22). Este arquivo é a única casa da árvore e a ratificação do dono acontece no gate da etapa `02_domain`. As decisões estão em [`_sprints/s01-nucleo-enoch/01_grilling/handovers/decisoes.md`](_sprints/s01-nucleo-enoch/01_grilling/handovers/decisoes.md) e são citadas por número (D#, item #), não copiadas. O vocabulário está em [`../CONTEXT.md`](../CONTEXT.md). O que o e01 entrega por sprint está na D22.

Convenção do Mix: o módulo `Enoch.Foo` mora em `lib/enoch/foo.ex`; um módulo e a pasta que guarda seus submódulos têm o mesmo nome (`lib/enoch/storage.ex` com `lib/enoch/storage/`). O módulo raiz `Enoch` mora em `lib/enoch.ex`.

## Árvore

```
enoch/
├── mix.exs                  pacote único, app OTP :enoch (D23, D37)
├── flake.nix                ambiente e comandos de projeto (D38)
├── Dockerfile               contêiner leve, SQLite em volume (D38, item 31)
├── lib/
│   ├── enoch.ex             API pública funcional por nome de instância (D32)
│   └── enoch/
│       ├── repo.ex          macro `use Enoch.Repo`, camada fina sobre a API (D32)
│       ├── application.ex   app OTP; só o que é global (D23)
│       ├── instance/        o que sobe por instância
│       │   ├── supervisor.ex   árvore de supervisão por instância (D32, D21)
│       │   ├── owner.ex        processo dono das tabelas, separado do transactor (D18, D21)
│       │   ├── admission.ex    admissão limitada, com estado fechado e aberto (D27, D34)
│       │   └── boot.ex         sequência de subida em sete passos (D34)
│       ├── transactor.ex    único escritor; serializa transações (D14, D21)
│       ├── db.ex            banco como valor: referências e base (D18, D16)
│       ├── schema/
│       │   ├── data.ex         forma canônica: lista de definições em dados (D31)
│       │   ├── dsl.ex          macros entity/attr, açúcar sobre os dados (D31)
│       │   ├── bootstrap.ex    atributos meta (D11, D31)
│       │   ├── registry.ex     registro do schema, legível por extensões (D24, D35)
│       │   ├── installer.ex    instalação aditiva, compatibilidade, deprecated, rename (D29)
│       │   └── migration.ex    migração de dados versionada (D29)
│       ├── tx/
│       │   ├── expand.ex       mapas viram operações de afirmar e retrair
│       │   ├── resolve.ex      tempids, lookup refs, cardinalidade, unicidade, imutabilidade (D5, D14, D26)
│       │   ├── function.ex     behaviour das funções de transação (D35)
│       │   ├── validate.ex     tipos, escala e normalização do decimal (D12, D13, D36)
│       │   └── report.ex       relatório da transação
│       ├── query/
│       │   ├── parser.ex       Elixir para AST de Datalog (D6)
│       │   ├── evaluator.ex    motor único: joins, predicados, negação, disjunção (D6, D33)
│       │   ├── aggregate.ex    count, sum, min, max (D9)
│       │   ├── rules.ex        regras nomeadas não recursivas (D10, D35)
│       │   ├── pull.ex         pull por nível do padrão (D33)
│       │   └── scan.ex         invólucro público do scan, equivalente a datoms (D7, D33)
│       ├── derived.ex       Enoch.verify_derived: valor materializado contra a regra (D30)
│       ├── storage.ex       behaviour do adaptador: varreduras, pushdown, versão do layout (D7, D34)
│       ├── storage/
│       │   └── contract_case.ex   suíte de contrato reutilizável por adaptadores (D24)
│       ├── adapters/
│       │   ├── memory.ex       ETS: histórico, estado atual, contador-base, recuperação (D18, D21)
│       │   └── sqlite.ex       SQLite via exqlite: log imutável, estado atual, persistência (D16, D23)
│       └── telemetry.ex     eventos de memória, fila, consultas mortas, linhas lidas (D21, D27)
├── config/                  config.exs e runtime.exs
├── priv/                    arquivo SQLite em desenvolvimento (D17, critério 4)
├── examples/                app de exemplo: prova a experiência de ponta a ponta (D17, D22 s05, item 31)
└── test/
    ├── support/             geradores de propriedades e auxiliares (D38)
    └── enoch/               espelha lib/enoch; a suíte de contrato roda nos dois adaptadores (D17)
```

## Pasta por sprint (D22)

| Região | s01 | s02 | s03 | s04 | s05 |
| --- | --- | --- | --- | --- | --- |
| `lib/enoch.ex`, `repo.ex`, `application.ex` | esqueleto | | `q`, `pull`, `as_of`, `history` | | |
| `instance/` | supervisor, owner, admission, boot (passos 1, 2, 3, 7) | passo do schema | registro de regras | versão do layout | migrações, limites |
| `transactor.ex` | add e retract crus | funções de transação | | | funções limitadas |
| `schema/`, `tx/` | | tudo (D29, D31, D26, D33) | | | `migration.ex` |
| `query/`, `derived.ex` | | | tudo (D33, D28, D30) | | |
| `storage.ex`, `storage/` | contrato inicial | | | roda nos dois adaptadores | |
| `adapters/memory.ex` | completo | | | | |
| `adapters/sqlite.ex` | | | | completo | |
| `telemetry.ex` | contador de linhas | | | | eventos completos |
| `examples/`, `Dockerfile`, `flake.nix` | | | | | exemplo e contêiner |

## O que não existe no e01

Ficam para o e02 ou depois: adaptadores MySQL e Postgres, eventos de transação, regras recursivas, componentes e navegação por entidade, corrente de hashes, excisão, registro de extensões e group commit (D1, D5, D9, D24, D27, D33). O compilador de Datalog para SQL e o dialeto por banco do chat foram descartados (D6).
