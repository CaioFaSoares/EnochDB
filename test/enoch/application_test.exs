defmodule Enoch.ApplicationTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  @app :enoch

  test "o app :enoch sobe com o registro global de instâncias" do
    capture_log(fn ->
      assert :ok = Application.stop(@app)
      assert {:ok, _apps} = Application.ensure_all_started(@app)

      assert @app in Enum.map(Application.started_applications(), &elem(&1, 0))
      assert Application.spec(@app, :mod) == {Enoch.Application, []}
    end)
  end
end
