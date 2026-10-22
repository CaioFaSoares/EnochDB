defmodule Enoch.DocsTest do
  @moduledoc """
  Each code and test folder of the tree has a `CONTEXT.md`, checked by listing (R35 in
  `docs/_sprints/s01-nucleo-enoch/03_spec/handovers/spec.md`).

  It reads only `lib/`, `test/` and `config/`, the folders the `flake.nix` test
  derivation carries: `docs/` is outside `projectSrc`, so a test reading it would
  fail in `nix run .#test`.
  """

  use ExUnit.Case, async: true

  @root Path.expand("../..", __DIR__)
  @folder_roots ["lib", "test", "config"]

  test "every code and test folder has a CONTEXT.md (R10, R35)" do
    missing =
      for folder <- folders(), not File.regular?(Path.join(folder, "CONTEXT.md")), do: folder

    assert missing == [], "folders without CONTEXT.md: #{inspect(missing)}"
  end

  defp folders do
    Enum.flat_map(@folder_roots, fn root ->
      path = Path.join(@root, root)

      [path | Path.wildcard(Path.join(path, "**/"))]
      |> Enum.filter(&File.dir?/1)
    end)
  end
end
