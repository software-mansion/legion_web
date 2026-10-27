defmodule LegionWeb.MarkupTest do
  use ExUnit.Case, async: true

  alias LegionWeb.Markup

  defp to_html({:safe, iodata}), do: IO.iodata_to_binary(iodata)

  describe "highlight/2" do
    test "highlights elixir via registered lexer" do
      html = Markup.highlight("def hello, do: :world", "elixir") |> to_html()
      assert html =~ "<span"
      assert html =~ "hello"
    end

    test "highlights lua via registered lexer" do
      html = Markup.highlight("local x = 1", "lua") |> to_html()
      assert html =~ "<span"
      assert html =~ "local"
    end

    test "falls back to escaped plaintext for unknown language" do
      html = Markup.highlight("<b>&</b>", "no-such-language") |> to_html()
      assert html == "&lt;b&gt;&amp;&lt;/b&gt;"
    end

    test "falls back to escaped plaintext for nil language" do
      html = Markup.highlight("<b>", nil) |> to_html()
      assert html == "&lt;b&gt;"
    end

    test "always returns a Phoenix.HTML safe tuple" do
      assert {:safe, _} = Markup.highlight("x", "elixir")
      assert {:safe, _} = Markup.highlight("x", "lua")
      assert {:safe, _} = Markup.highlight("x", nil)
    end
  end

  describe "markdown/1" do
    test "highlights lua fenced block" do
      html = Markup.markdown("```lua\nlocal x = 1\n```") |> to_html()
      assert html =~ ~s(<code class="language-lua highlight">)
      assert html =~ "<span"
    end

    test "highlights elixir fenced block" do
      html = Markup.markdown("```elixir\ndef x, do: 1\n```") |> to_html()
      assert html =~ ~s(<code class="language-elixir highlight">)
      assert html =~ "<span"
    end

    test "unescapes markdown entities before lexing" do
      html = Markup.markdown("```elixir\nx <> \"a\"\n```") |> to_html()
      refute html =~ "&amp;lt;"
      assert html =~ "&lt;&gt;"
    end

    test "leaves fenced block with unknown language as plain code" do
      html = Markup.markdown("```text\nhello <world>\n```") |> to_html()
      refute html =~ "<span"
      assert html =~ "hello &lt;world&gt;"
    end

    test "leaves unfenced code block untouched" do
      html = Markup.markdown("```\nplain\n```") |> to_html()
      refute html =~ "highlight"
      assert html =~ "plain"
    end

    test "renders ordinary markdown" do
      html = Markup.markdown("# Title\n\nsome *text*") |> to_html()
      assert html =~ "<h1>"
      assert html =~ "<em>text</em>"
    end

    test "escapes raw HTML blocks instead of passing them through" do
      html = Markup.markdown("<script>alert(1)</script>\n\nsafe *text*") |> to_html()
      refute html =~ "<script>"
      assert html =~ "&lt;script&gt;"
      assert html =~ "<em>text</em>"
    end

    test "escapes raw HTML tags with attributes" do
      html = Markup.markdown("<img src=x onerror=alert(1)>") |> to_html()
      refute html =~ "<img"
      assert html =~ "&lt;img"
    end

    test "escapes inline HTML" do
      html = Markup.markdown("hello <b onmouseover=alert(1)>bold</b>") |> to_html()
      refute html =~ "<b "
      assert html =~ "&lt;b"
    end

    test "drops javascript: link targets" do
      html = Markup.markdown("[click](javascript:alert(1))") |> to_html()
      refute html =~ "javascript:"
      assert html =~ "click"
    end

    test "drops data: image sources" do
      html = Markup.markdown("![x](data:text/html;base64,PHNjcmlwdD4=)") |> to_html()
      refute html =~ "data:"
    end

    test "renders tables, strikethrough and bare links" do
      html = Markup.markdown("| a |\n|---|\n| 1 |\n\n~~gone~~ https://example.com") |> to_html()
      assert html =~ "<table>"
      assert html =~ "<del>gone</del>"
      assert html =~ ~s(<a href="https://example.com">)
    end

    test "renders malformed markdown best-effort instead of raising" do
      assert {:safe, _} = Markup.markdown("[unclosed](link\n\n> *")
    end
  end
end
