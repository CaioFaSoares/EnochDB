{
  description = "EnochDB — ambiente e comandos do projeto (D38)";

  # Toolchain preso por revisão do nixpkgs: o alvo da ADR-0009 é
  # `beam.packages.erlang_29.elixir_1_20` (Elixir 1.20.4 sobre OTP 29.1.1),
  # não o `beamPackages.elixir` padrão, que ainda é o 1.18.
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/319e4cebef10cbb636c6ea392137b52ad105336a";

  outputs =
    { self, nixpkgs }:
    let
      lib = nixpkgs.lib;

      systems = [
        "aarch64-darwin"
        "x86_64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];

      root = self.outPath;

      # Mantém só as entradas de topo pedidas: `docs/`, `.omp/`, `examples/` e o
      # resto não mexem no hash das derivações.
      only =
        names: path: _type:
        let
          rel = lib.removePrefix "${root}/" (toString path);
        in
        rel == "" || builtins.elem (lib.head (lib.splitString "/" rel)) names;

      perSystem =
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};

          # O conjunto do nixpkgs prende `elixir` no 1.18.5; o alvo é o 1.20.4
          # (ADR-0009), e dele saem o shell, o `mix deps.get` e os testes.
          beam = pkgs.beam.packages.erlang_29.overrideScope (
            _final: prev: { elixir = prev.elixir_1_20; }
          );
          inherit (beam) elixir;

          projectSrc = lib.cleanSourceWith {
            src = root;
            filter = only [
              ".formatter.exs"
              "config"
              "lib"
              "mix.exs"
              "mix.lock"
              "priv"
              "test"
            ];
          };

          # `mix deps.get` só lê o projeto e o lock: o hash das dependências não
          # muda quando `lib/` ou `test/` mudam.
          depsSrc = lib.cleanSourceWith {
            src = root;
            filter = only [
              "config"
              "mix.exs"
              "mix.lock"
            ];
          };

          mixDeps = beam.fetchMixDeps {
            pname = "enoch-deps";
            version = "0.1.0";
            src = depsSrc;
            mixEnv = "test";
            hash = "sha256-htSjMYLfvI28lRwBl81tK+wOif5APz2VsinoxXHQgRc=";
          };

          tests = beam.buildMix {
            name = "enoch-test";
            version = "0.1.0";
            src = projectSrc;
            mixEnv = "test";
            mixFodDeps = mixDeps;
            # O `buildMix` não traz os hooks das dependências; sem eles o `deps/`
            # baixado não entra no caminho e os testes não acham as aplicações.
            nativeBuildInputs = [
              beam.mixFodDepsSetupHook
              beam.mixDepsCompileHook
              # O `mix` instala o rebar no `MIX_HOME`, que fica em `$HOME`.
              pkgs.writableTmpDirAsHomeHook
              # O NIF do `exqlite` compila C no `mix deps.compile`.
              pkgs.gnumake
            ];
            env = {
              MIX_REBAR = "${beam.rebar}/bin/rebar";
              MIX_REBAR3 = "${beam.rebar3}/bin/rebar3";
            };
            postBuild = ''
              set -o pipefail
              mix test --no-deps-check | tee test.log
            '';
            installPhase = ''
              runHook preInstall
              mkdir -p $out/bin
              # Só o resumo entra na saída: a semente e os tempos do ExUnit mudam
              # a cada execução e deixariam a derivação não determinística. O log
              # completo fica no log do build (`nix log`).
              printf '%s\n' "$(tail -n 1 test.log)" > $out/resultado
              cat > $out/bin/enoch-test <<EOF
              #!${pkgs.runtimeShell}
              exec ${pkgs.coreutils}/bin/cat ${placeholder "out"}/resultado
              EOF
              chmod +x $out/bin/enoch-test
              runHook postInstall
            '';
          };

          estado = pkgs.writeShellScriptBin "estado" ''
            export PATH=${lib.makeBinPath [
              pkgs.bash
              pkgs.coreutils
              pkgs.gawk
            ]}:$PATH
            exec ${pkgs.bash}/bin/bash ${root}/docs/_index/estado.sh "$@"
          '';
        in
        {
          devShells.default = pkgs.mkShell {
            packages = [
              elixir
              beam.hex
              beam.rebar3
              pkgs.gnumake
              pkgs.git
              pkgs.cacert
            ];
          };

          apps = {
            test = {
              type = "app";
              program = "${tests}/bin/enoch-test";
            };
            estado = {
              type = "app";
              program = "${estado}/bin/estado";
            };
          };

          checks.test = tests;
        };

      forAllSystems = lib.genAttrs systems;
    in
    {
      devShells = forAllSystems (system: (perSystem system).devShells);
      apps = forAllSystems (system: (perSystem system).apps);
      checks = forAllSystems (system: (perSystem system).checks);
    };
}
