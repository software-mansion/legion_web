defmodule LegionWeb.Components.Trace do
  @moduledoc false

  use LegionWeb, :html

  alias LegionWeb.Components.Usage
  alias LegionWeb.{Helpers, Markup}

  attr :items, :list, required: true
  attr :language, :string, default: nil

  def render(assigns) do
    ~H"""
    <div
      id="trace-container"
      class="flex-1 overflow-y-auto px-6 py-4 space-y-1 font-mono text-xs text-black"
      phx-hook="AutoScroll"
    >
      <div :if={@items == []} class="flex items-center justify-center h-full">
        <p class="text-black/40 italic">Waiting for events&hellip;</p>
      </div>
      <%= for item <- @items do %>
        <%= case item do %>
          <% {:subagent, name, sub_items} -> %>
            <details
              id={"subagent-#{sub_item_seq(sub_items)}"}
              class="animate-fade-in my-1"
              phx-hook="DetailsState"
            >
              <summary class="cursor-pointer flex gap-2 items-center py-1 px-3 bg-sol-base2/50 border border-sol-base1/20 rounded-lg hover:bg-sol-base2">
                <span class="text-sol-cyan font-semibold text-xs">{name}</span>
                <span class="text-black/50 text-xs">{length(sub_items)} events</span>
              </summary>
              <div class="ml-4 pl-3 border-l-2 border-sol-cyan/30 space-y-1 py-1">
                <div :for={sub <- sub_items} id={"item-#{item_seq(sub)}"}>
                  <.render_item item={sub} language={@language} />
                </div>
              </div>
            </details>
          <% {_type, data} -> %>
            <div id={"item-#{data.seq}"} class="animate-fade-in">
              <.render_item item={item} language={@language} />
            </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  # Item renderers

  defp render_item(%{item: {:message, data}} = assigns) do
    assigns = assign(assigns, :data, data)

    ~H"""
    <div class="flex gap-2 items-start bg-sol-blue/10 border border-sol-blue/20 rounded-lg px-3 py-2.5 my-2">
      <span class="shrink-0 w-16 tabular-nums">{format_ts(@data.ts)}</span>
      <span class="flex-1">{Helpers.truncate(@data.text, 200)}</span>
    </div>
    """
  end

  defp render_item(%{item: {:human_response, data}} = assigns) do
    assigns = assign(assigns, :data, data)

    ~H"""
    <div class="flex gap-2 items-start bg-sol-yellow/10 border border-sol-yellow/20 rounded-lg px-3 py-2.5 my-2">
      <span class="shrink-0 w-16 tabular-nums">{format_ts(@data.ts)}</span>
      <span class="flex-1">{Helpers.truncate(@data.text, 200)}</span>
    </div>
    """
  end

  defp render_item(%{item: {:exception, data}} = assigns) do
    assigns = assign(assigns, :data, data)

    ~H"""
    <div class="flex gap-2 items-start bg-sol-red/10 border border-sol-red/20 rounded-lg px-3 py-2.5 my-2">
      <span class="shrink-0 w-16 tabular-nums">{format_ts(@data.ts)}</span>
      <span class="text-sol-red font-semibold">error</span>
      <span class="text-sol-red/80 flex-1">{format_exception(@data.reason)}</span>
    </div>
    """
  end

  defp render_item(%{item: {:step, data}} = assigns) do
    assigns =
      assigns
      |> assign(:data, data)
      |> assign(:human_question, extract_human_question(data.code))

    ~H"""
    <div class="flex gap-2 items-start py-0.5">
      <span class="shrink-0 w-16 tabular-nums">{format_ts(@data.ts)}</span>
      <%= if @data.action do %>
        <.render_step_body data={@data} human_question={@human_question} language={@language} />
      <% else %>
        <.render_response_only data={@data} />
      <% end %>
      <span class="ml-auto shrink-0 flex items-center gap-3 text-black/50 tabular-nums">
        <span :if={@data.duration}>{format_duration(@data.duration)}</span>
        <Usage.chip :if={@data.usage != []} usage={@data.usage} />
      </span>
    </div>
    """
  end

  defp render_item(%{item: {:eval_error, data}} = assigns) do
    assigns = assign(assigns, :data, data)

    ~H"""
    <div class={[
      "flex gap-2 items-start py-0.5",
      @data.is_timeout && "bg-sol-orange/8 border border-sol-orange/20 rounded-lg p-2.5 my-1"
    ]}>
      <span class="shrink-0 w-16 tabular-nums">{format_ts(@data.ts)}</span>
      <span class={if @data.is_timeout, do: "text-sol-orange", else: "text-sol-red"}>
        {if @data.is_timeout, do: "\u23F1", else: "\u2717"}
      </span>
      <div class="flex-1 min-w-0">
        <pre class={[
          "p-3 rounded-lg overflow-x-auto whitespace-pre-wrap text-xs",
          if(@data.is_timeout,
            do: "text-sol-orange",
            else: "bg-sol-red/8 border border-sol-red/20 text-sol-red"
          )
        ]}>{format_eval_error(@data.error)}</pre>
      </div>
    </div>
    """
  end

  defp render_item(%{item: {:unknown, data}} = assigns) do
    assigns = assign(assigns, :data, data)

    ~H"""
    <div class="flex gap-2 items-start py-0.5">
      <span class="shrink-0 w-16 tabular-nums">{format_ts(@data.ts)}</span>
      <span>{inspect(@data.type)}</span>
    </div>
    """
  end

  # Step sub-renders

  attr :data, :map, required: true

  defp render_response_only(assigns) do
    ~H"""
    <%= cond do %>
      <% @data.error -> %>
        <span class="text-sol-red/70 italic">{format_llm_error(@data.error)}</span>
      <% has_result?(@data.result) -> %>
        <div class="flex-1 min-w-0 p-3 bg-sol-green/8 border border-sol-green/20 rounded-lg">
          <div class="text-black trace-prose">
            {render_markdown(extract_response(@data.result))}
          </div>
        </div>
      <% true -> %>
        <span class="text-black/40 italic">(response)</span>
    <% end %>
    """
  end

  attr :data, :map, required: true
  attr :human_question, :string, default: nil
  attr :language, :string, default: nil

  defp render_step_body(assigns) do
    ~H"""
    <div class="flex-1 min-w-0">
      <%= if @human_question do %>
        <div class="flex gap-2 items-center">
          <span class="text-sol-orange font-semibold">?</span>
          <span class="text-black">{@human_question}</span>
        </div>
      <% else %>
        <span class={action_class(@data.action)}>{@data.action}</span>
        <details :if={@data.code && @data.code != ""} class="mt-1.5 code-details">
          <summary class="cursor-pointer text-black/60 hover:text-black text-xs">
            <span class="show-label">show code</span>
            <span class="hide-label">hide code</span>
          </summary>
          <pre class="mt-1.5 p-3 bg-sol-base2 rounded-lg overflow-x-auto whitespace-pre-wrap border border-sol-base1/20 highlight">{Markup.highlight(@data.code, @language)}</pre>
        </details>
        <div
          :if={@data.action in ["return", "done"] && has_result?(@data.result)}
          class="mt-1.5 p-3 bg-sol-green/8 border border-sol-green/20 rounded-lg"
        >
          <div class="text-black trace-prose">
            {render_markdown(extract_response(@data.result))}
          </div>
        </div>
        <.render_eval_inline eval={@data.eval} />
      <% end %>
    </div>
    """
  end

  attr :eval, :map, default: nil

  defp render_eval_inline(%{eval: nil} = assigns), do: ~H""

  defp render_eval_inline(%{eval: %{success: true}} = assigns) do
    assigns = assign(assigns, :has_error, error_result?(assigns.eval.result))

    ~H"""
    <div
      :if={has_result?(@eval.result)}
      class={[
        "mt-1.5 p-3 rounded-lg border overflow-x-auto",
        if(@has_error,
          do: "bg-sol-red/8 border-sol-red/20",
          else: "bg-sol-base2 border-sol-base1/20"
        )
      ]}
    >
      <pre class={[
        "text-xs whitespace-pre-wrap",
        @has_error && "text-sol-red"
      ]}>{format_eval_result(@eval.result)}</pre>
    </div>
    """
  end

  defp render_eval_inline(assigns) do
    assigns = assign(assigns, :is_timeout, match?(%{type: :timeout}, assigns.eval.error))

    ~H"""
    <div class={[
      "mt-1.5 p-3 rounded-lg overflow-x-auto",
      if(@is_timeout,
        do: "bg-sol-orange/8 border border-sol-orange/20",
        else: "bg-sol-red/8 border border-sol-red/20"
      )
    ]}>
      <pre class={[
        "text-xs whitespace-pre-wrap",
        if(@is_timeout, do: "text-sol-orange", else: "text-sol-red")
      ]}>{format_eval_error(@eval.error)}</pre>
    </div>
    """
  end

  # Helpers

  defp item_seq({_type, %{seq: seq}}), do: seq
  defp item_seq(_), do: 0

  defp sub_item_seq([first | _]), do: item_seq(first)
  defp sub_item_seq(_), do: 0

  defp has_result?(nil), do: false
  defp has_result?(""), do: false
  defp has_result?(_), do: true

  defp error_result?({:error, _}), do: true

  defp error_result?(tuple) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> Enum.any?(&error_result?/1)

  defp error_result?(list) when is_list(list), do: Enum.any?(list, &error_result?/1)
  defp error_result?(_), do: false

  defp format_ts(ms) when is_integer(ms) do
    ms
    |> DateTime.from_unix!(:millisecond)
    |> Calendar.strftime("%H:%M:%S")
  end

  defp format_ts(_), do: "--:--:--"

  defp format_duration(nil), do: nil

  # Legion span durations are System.monotonic_time/0 diffs in native units.
  defp format_duration(duration) when is_integer(duration) do
    Helpers.format_ms(System.convert_time_unit(duration, :native, :millisecond))
  end

  defp format_duration(_), do: nil

  defp extract_human_question(nil), do: nil

  defp extract_human_question(code) when is_binary(code) do
    case Regex.run(~r/HumanTool\.ask\(\s*"((?:[^"\\]|\\.)*)"\s*\)/, code) do
      [_, question] -> String.replace(question, "\\\"", "\"")
      _ -> nil
    end
  end

  defp action_class("eval_and_continue"), do: "text-sol-blue"
  defp action_class("eval_and_complete"), do: "text-sol-green"
  defp action_class("return"), do: "text-sol-green font-semibold"
  defp action_class("done"), do: "text-black"
  defp action_class(_), do: "text-black"

  defp format_eval_result(result) do
    formatted = inspect(result, pretty: true, limit: 100, printable_limit: 2000)

    if String.length(formatted) > 1500 do
      String.slice(formatted, 0, 1500) <> "\n... (truncated)"
    else
      formatted
    end
  end

  defp format_eval_error(%{message: message}) when is_binary(message), do: message
  defp format_eval_error(error) when is_exception(error), do: Exception.message(error)
  defp format_eval_error(error), do: inspect(error, pretty: true, limit: 50)

  defp format_exception(reason) when is_exception(reason), do: Exception.message(reason)
  defp format_exception(reason), do: inspect(reason, pretty: true, limit: 50)

  defp format_llm_error(%{message: msg}) when is_binary(msg), do: msg
  defp format_llm_error(error) when is_exception(error), do: Exception.message(error)
  defp format_llm_error(error) when is_binary(error), do: error
  defp format_llm_error(error), do: inspect(error, pretty: true, limit: 50)

  defp extract_response(result) when is_map(result) do
    case Map.get(result, "response") do
      nil -> format_result(result)
      response when is_binary(response) -> response
      other -> inspect(other)
    end
  end

  defp extract_response(result) when is_binary(result), do: result
  defp extract_response(result), do: inspect(result, pretty: true, limit: 500)

  defp format_result(result) when is_map(result) do
    Jason.encode!(result, pretty: true)
  rescue
    _ -> inspect(result, pretty: true, limit: 500)
  end

  defp format_result(result), do: inspect(result, pretty: true, limit: 500)

  defp render_markdown(text) when is_binary(text), do: Markup.markdown(text)
  defp render_markdown(other), do: other
end
