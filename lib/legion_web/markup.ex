defmodule LegionWeb.Markup do
  @moduledoc """
  Turns markdown and source code into safe HTML for the dashboard.

  Languages are addressed by their `Makeup.Registry` name (`"elixir"`,
  `"lua"`, ...). Any lexer registered with Makeup works; a language with no
  registered lexer degrades to HTML-escaped plaintext rather than raising.
  """

  @doc """
  Highlights `code` as `language`, returning safe HTML for use inside a
  `<pre class="highlight">` or `<code class="highlight">`.

  Unknown or `nil` `language` returns the escaped code with no markup.
  """
  @spec highlight(String.t(), String.t() | nil) :: Phoenix.HTML.safe()
  def highlight(code, language) when is_binary(code) do
    case language && Makeup.Registry.get_lexer_by_name(language) do
      {lexer, opts} ->
        Makeup.highlight_inner_html(code, lexer: lexer, lexer_options: opts)

      _ ->
        code |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
    end
    |> Phoenix.HTML.raw()
  end

  @doc """
  Renders markdown to safe HTML, highlighting every fenced code block whose
  info string names a registered lexer. Other fenced blocks render as plain
  `<pre><code>`.

  Raw HTML in the markdown is escaped and rendered as text, and links or
  images with dangerous URLs (`javascript:`, ...) lose their target, so
  markdown from an LLM or a user cannot inject markup into the dashboard.
  Malformed markdown renders best-effort instead of raising.
  """
  @spec markdown(String.t()) :: Phoenix.HTML.safe()
  def markdown(text) when is_binary(text) do
    text
    |> MDEx.parse_document!(
      extension: [table: true, strikethrough: true, autolink: true],
      render: [escape: true]
    )
    |> MDEx.traverse_and_update(&highlight_code_block/1)
    |> MDEx.to_html!()
    |> Phoenix.HTML.raw()
  end

  # Not MDEx's `codefence_renderers`: it parses the info string as shell
  # arguments and raises on an unbalanced quote, e.g. ```foo "
  defp highlight_code_block(%MDEx.CodeBlock{info: info, literal: code} = node) do
    [language | _metadata] = String.split(info, ~r/\s/, parts: 2)

    case Makeup.Registry.get_lexer_by_name(language) do
      nil ->
        node

      _lexer ->
        {:safe, highlighted} = highlight(code, language)

        %MDEx.Raw{
          literal:
            ~s(<pre><code class="language-#{language} highlight">#{highlighted}</code></pre>)
        }
    end
  end

  defp highlight_code_block(node), do: node
end
