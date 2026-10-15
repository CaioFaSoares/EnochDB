# Glossário do EnochDB

Vocabulário de domínio aprovado do projeto. Termos só entram após decisão explícita; a conversa inicial não é fonte de definições canônicas.

O processo e os termos de sprint (step, sprint, handover) estão em [`docs/PROCESS.md`](docs/PROCESS.md).

A arquitetura de pastas do pacote `enoch` está em [`docs/arquitetura.md`](docs/arquitetura.md); a issue [#1](https://github.com/CaioFaSoares/EnochDB/issues/1) cria as pastas, cada uma com um `CONTEXT.md`, antes de qualquer código.

## Termos de domínio

### Quem usa e quem amplia o Enoch

**Aplicação**:
Projeto do usuário que depende do Enoch e define o schema para um domínio, como o Obol.
_Avoid_: app cliente, projeto cliente. Não confundir com a aplicação OTP do Erlang: para esta, diga "app OTP".

**Extensão**:
Código reutilizável que amplia o Enoch e que mais de uma aplicação pode usar. Tem três tipos: de storage, de integração e de domínio.
_Avoid_: plugin, addon, módulo.

**Adaptador**:
Módulo que implementa o contrato de storage do Enoch para um banco. O `Memory` e o SQLite acompanham o pacote como adaptadores.
_Avoid_: driver.

**Extensão de storage**:
Adaptador para um banco além dos que acompanham o pacote, como o de Postgres, interno ou distribuído à parte.
_Avoid_: driver.

**Extensão de integração**:
Extensão que expõe os dados do Enoch a outro sistema ou protocolo a partir do schema, como um servidor GraphQL.
_Avoid_: conector, gateway.

**Extensão de domínio**:
Extensão que reúne regras de um domínio reutilizáveis por mais de uma aplicação, como o ledger. Um pedaço de domínio que só uma aplicação usa fica nela e não é extensão.
_Avoid_: biblioteca de domínio, módulo de domínio.

### Fatos, tempo e leitura

**Datom**:
Um fato atômico: uma entidade tem um valor para um atributo, afirmado ou retraído por uma transação.
_Avoid_: linha, registro, tupla.

**Transação**:
Conjunto de afirmações e retrações aplicadas juntas, tudo ou nada, que recebe um número de ordem global.
_Avoid_: commit, lote.

**Transactor**:
O único escritor de uma instância do banco; serializa as transações.
_Avoid_: writer, escritor.

**Base**:
O número de ordem da última transação visível a um banco como valor.
_Avoid_: versão, snapshot.

**Banco como valor**:
Visão imutável do banco em uma base; consultas contra o mesmo valor dão sempre o mesmo resultado.
_Avoid_: conexão, snapshot.

**Log**:
Registro imutável e completo de todas as transações; é a fonte de verdade.
_Avoid_: auditoria, journal.

**Estado atual**:
Os datoms vivos hoje. É derivado e reconstruível a partir do log, nunca fonte de verdade.
_Avoid_: tabela atual, cache.

**Histórico**:
Visão do banco sem filtro de tempo, que mostra afirmações e retrações de todas as transações.
_Avoid_: auditoria, versões.
