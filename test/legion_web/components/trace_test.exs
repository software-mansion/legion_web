defmodule LegionWeb.Components.TraceTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias LegionWeb.Components.Trace

  defp step(code, usage \\ []) do
    {:step,
     %{
       seq: 1,
       ts: 1_700_000_000_000,
       action: "eval_and_continue",
       code: code,
       result: nil,
       error: nil,
       duration: nil,
       eval: nil,
       usage: usage
     }}
  end

  describe "usage chip" do
    test "renders the chip on a step with usage" do
      usage = %{"input_tokens" => 4_930, "output_tokens" => 132, "at" => 1_700_000_158_000}
      html = render_component(&Trace.render/1, items: [step("x", [usage])], language: nil)

      assert html =~ "↑4.9k"
      assert html =~ "22:15:58 UTC"
    end

    test "renders no chip on a step without usage" do
      html = render_component(&Trace.render/1, items: [step("x")], language: nil)

      refute html =~ "↑"
      refute html =~ "data-note"
    end
  end

  describe "step code highlighting" do
    test "highlights step code in the given language" do
      html = render_component(&Trace.render/1, items: [step("local x = 1")], language: "lua")
      assert html =~ ~s(<span class="kd">local</span>)
    end

    test "highlights elixir when language is elixir" do
      html = render_component(&Trace.render/1, items: [step("def x")], language: "elixir")
      assert html =~ ~s(<span class="k">def</span>)
    end

    test "renders escaped plaintext when language is nil" do
      html = render_component(&Trace.render/1, items: [step("local x <> 1")], language: nil)
      refute html =~ ~s(class="kd")
      assert html =~ "local x &lt;&gt; 1"
    end
  end
end
