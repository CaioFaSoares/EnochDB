# ADR-0009 — Pacote único `enoch`, SQLite via `exqlite` e toolchain estável mais recente

- **Status:** aceita
- **Data:** 2026-10-15
- **Supera:** —

## Contexto

O dono quer o banco pronto para provar o conceito, não uma arquitetura de pacotes. Vários pacotes no e01 adiariam essa prova, e o Obol, primeiro cliente real, só entra no e03. Também é preciso fixar um ambiente reproduzível: o atributo padrão `beamPackages.elixir` do nixpkgs dá Elixir 1.18.5, o que diverge do alvo, e o contêiner precisa ser leve.

## Decisão

- Um único pacote `enoch`, com o app OTP `:enoch` e os módulos sob `Enoch`. Os adaptadores são módulos (`Enoch.Adapters.SQLite`, `Enoch.Adapters.Memory`). O Obol não entra no e01 nem no e02.
- Driver SQLite: `exqlite`. O SQLite do Enoch é o embutido nele, com a versão presa à do `exqlite`.
- Alvo: Elixir 1.20.4 com OTP 29. O piso em `mix.exs` acompanha o alvo (`~> 1.20`), escolha do agente aceita junto com o conjunto no gate do `01_grilling`.
- Dependências: `decimal ~> 3.2`, `telemetry ~> 1.0`; testes com ExUnit e `stream_data ~> 1.0` (só em teste).
- Nix: o flake fixa `beam.packages.erlang_29.elixir_1_20` e serve para chamar, não só para entrar no shell (`nix run .#test`, `nix run .#estado`, `nix flake check`, um pacote para a imagem). Os comandos são proposta do agente, a ajustar na spec.
- Contêiner: `Dockerfile` em dois estágios sobre Alpine, por prudência (iniciativa do agente, aceita junto com o conjunto no gate do `01_grilling`): compilar com `build-base` em `hexpm/elixir:1.20.4-erlang-29.1.2-alpine-*` e rodar o `mix release` numa imagem `alpine` enxuta com `libstdc++`, `ncurses-libs` e `openssl`.
- O SQLite fica embutido no contêiner do back, sem volume externo obrigatório (dono, 2026-10-15). O dono quer poder desabilitá-lo, se possível; a forma (persistência opcional ou adaptador desligável por configuração) não foi escolhida e fica para a spec.

## Opções consideradas

- **Pacote único:** o e01 prova o conceito sem coordenar pacotes.
- **Vários pacotes no e01:** rejeitado pelo dono.
- **Base Alpine (cerca de 49 MB comprimidos):** escolhida contra as bases Debian e Ubuntu, de 80 a 103 MB.
- **`beamPackages.elixir` padrão do nixpkgs:** rejeitado; é o 1.18.5.

## Consequências

- Verificado em 2026-10-14 e 2026-10-15: com Elixir 1.20.4 e OTP 29.1.1, o `exqlite` 0.42.0 compila e roda um teste de fumaça com `PRAGMA journal_mode = WAL`, tabela `STRICT, WITHOUT ROWID` com coluna `ANY` e índice parcial; o SQLite embutido ali é o 3.53.4. Os nomes `enoch`, `enoch_db` e `enochdb` estão livres no Hex; o pacote não foi publicado.
- A divergência de patch do OTP (29.1.1 no nixpkgs, 29.1.2 na imagem) é aceita.
- **Não verificado**, e o app de exemplo da s05 precisa verificar: o NIF pré-compilado do `exqlite` em Alpine (`aarch64` e `x86_64`), o `mix release` na imagem enxuta e o modo WAL em arquivo sob musl. Também não foram testados OTP 28 e Linux fora do contêiner.
- Se o NIF pré-compilado funcionar em Alpine, o estágio de build deixa de precisar de `build-base` e a spec simplifica. Uma imagem construída pelo flake, sem Docker, é alternativa a avaliar na spec.

## Referências

- Decisões D23, D24, D37, D38 e itens 6, 9, 31, 40 em [`decisoes.md`](../_sprints/s01-nucleo-enoch/01_grilling/handovers/decisoes.md).
- Tracker (GitHub Issues): [`../agents/README.md`](../agents/README.md).
