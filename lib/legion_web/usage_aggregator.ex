defmodule LegionWeb.UsageAggregator do
  @moduledoc """
  Aggregates and formats the per-request LLM usage entries returned by
  `c:LegionWeb.AgentTracker.get_usage/1`.

  Entries are the string-keyed maps Legion records for each LLM request
  (`"input_tokens"`, `"output_tokens"`, `"cached_tokens"`, `"reasoning_tokens"`,
  `"total_cost"`, `"at"`, ...). Missing counters count as zero; cost is `nil`
  until at least one entry reports `"total_cost"`.
  """

  @type totals :: %{
          requests: non_neg_integer(),
          input: non_neg_integer(),
          output: non_neg_integer(),
          cached: non_neg_integer(),
          reasoning: non_neg_integer(),
          cost: number() | nil
        }

  @empty %{requests: 0, input: 0, output: 0, cached: 0, reasoning: 0, cost: nil}

  @doc "Sums token counters and cost across usage entries."
  @spec totals([map()]) :: totals()
  def totals(usage) when is_list(usage) do
    Enum.reduce(usage, @empty, fn entry, acc ->
      %{
        requests: acc.requests + 1,
        input: acc.input + tokens(entry, "input_tokens"),
        output: acc.output + tokens(entry, "output_tokens"),
        cached: acc.cached + tokens(entry, "cached_tokens"),
        reasoning: acc.reasoning + tokens(entry, "reasoning_tokens"),
        cost: add_cost(acc.cost, entry["total_cost"])
      }
    end)
  end

  @doc "Reads one token counter from an entry, treating missing values as zero."
  @spec tokens(map(), String.t()) :: non_neg_integer()
  def tokens(entry, key) do
    case entry[key] do
      value when is_integer(value) -> value
      _ -> 0
    end
  end

  @doc ~S|Abbreviates a token count: `842`, `12.3k`, `1.25M`.|
  @spec format_tokens(integer()) :: String.t()
  def format_tokens(n) when is_integer(n) and n < 1_000, do: Integer.to_string(n)

  def format_tokens(n) when is_integer(n) and n < 1_000_000 do
    case Float.round(n / 1_000, 1) do
      1000.0 -> format_tokens(1_000_000)
      v -> "#{v}k"
    end
  end

  def format_tokens(n) when is_integer(n), do: "#{Float.round(n / 1_000_000, 2)}M"

  @doc "Formats a dollar cost to three decimals, or `nil` when unknown."
  @spec format_cost(number() | nil) :: String.t() | nil
  def format_cost(nil), do: nil
  def format_cost(cost) when is_number(cost) and cost > 0 and cost < 0.001, do: "<$0.001"

  def format_cost(cost) when is_number(cost),
    do: "$#{:erlang.float_to_binary(cost / 1, decimals: 3)}"

  @doc ~S|Groups a count's thousands with commas: `4,930`.|
  @spec format_count(integer()) :: String.t()
  def format_count(n) when is_integer(n) do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end

  @doc """
  Plain-text hover card for a list of usage entries.

  A time line, then aligned columns for tokens and cost. One entry gets its
  request time; several get the request count and their time span. Meant for
  `white-space: pre` rendering in a monospace font.

      22:15:58 UTC
      input    4,930   cached     4,000
      output     132   reasoning    640
      cost    $0.003   estimated at list prices
  """
  @spec card([map()]) :: String.t()
  def card(entries) when is_list(entries) do
    totals = totals(entries)

    Enum.join(
      [
        time_line(entries),
        row("input", format_count(totals.input), "cached", format_count(totals.cached)),
        row("output", format_count(totals.output), "reasoning", format_count(totals.reasoning)),
        cost_line(totals.cost)
      ],
      "\n"
    )
  end

  defp time_line([entry]), do: "#{format_time(entry["at"])} UTC"

  defp time_line(entries) do
    first = List.first(entries)
    last = List.last(entries)

    "#{length(entries)} requests · #{format_time(first["at"])} – #{format_time(last["at"])} UTC"
  end

  defp row(label, value, second_label, second_value) do
    String.pad_trailing(label, 6) <>
      String.pad_leading(value, 8) <>
      "   " <>
      String.pad_trailing(second_label, 10) <>
      String.pad_leading(second_value, 6)
  end

  defp cost_line(nil), do: String.pad_trailing("cost", 6) <> String.pad_leading("—", 8)

  defp cost_line(cost) do
    String.pad_trailing("cost", 6) <>
      String.pad_leading(format_cost(cost), 8) <> "   estimated at list prices"
  end

  defp format_time(ms) when is_integer(ms) do
    ms |> DateTime.from_unix!(:millisecond) |> Calendar.strftime("%H:%M:%S")
  end

  defp format_time(_), do: "--:--:--"

  defp add_cost(acc, cost) when is_number(cost), do: (acc || 0) + cost
  defp add_cost(acc, _), do: acc
end
