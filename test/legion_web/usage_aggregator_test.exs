defmodule LegionWeb.UsageAggregatorTest do
  use ExUnit.Case, async: true

  alias LegionWeb.UsageAggregator, as: Usage

  describe "totals/1" do
    test "sums token counters and cost across entries" do
      usage = [
        %{
          "input_tokens" => 1_000,
          "output_tokens" => 100,
          "cached_tokens" => 400,
          "reasoning_tokens" => 0,
          "total_cost" => 0.01,
          "at" => 1
        },
        %{"input_tokens" => 2_000, "output_tokens" => 50, "reasoning_tokens" => 30, "at" => 2}
      ]

      assert Usage.totals(usage) == %{
               requests: 2,
               input: 3_000,
               output: 150,
               cached: 400,
               reasoning: 30,
               cost: 0.01
             }
    end

    test "reports nil cost when no entry carries one" do
      assert %{requests: 1, cost: nil} = Usage.totals([%{"input_tokens" => 1}])
    end

    test "is empty for no entries" do
      assert Usage.totals([]) == %{
               requests: 0,
               input: 0,
               output: 0,
               cached: 0,
               reasoning: 0,
               cost: nil
             }
    end
  end

  describe "format_tokens/1" do
    test "abbreviates thousands and millions" do
      assert Usage.format_tokens(842) == "842"
      assert Usage.format_tokens(12_345) == "12.3k"
      assert Usage.format_tokens(1_250_000) == "1.25M"
    end
  end

  describe "format_cost/1" do
    test "formats dollars to three decimals" do
      assert Usage.format_cost(0.0421) == "$0.042"
      assert Usage.format_cost(0.0002) == "<$0.001"
      assert Usage.format_cost(nil) == nil
    end
  end

  describe "format_count/1" do
    test "groups thousands with commas" do
      assert Usage.format_count(0) == "0"
      assert Usage.format_count(842) == "842"
      assert Usage.format_count(4_930) == "4,930"
      assert Usage.format_count(1_250_000) == "1,250,000"
    end
  end

  describe "card/1" do
    @entry %{
      "input_tokens" => 4_930,
      "output_tokens" => 132,
      "cached_tokens" => 4_000,
      "reasoning_tokens" => 640,
      "total_cost" => 0.0031,
      "at" => 1_700_000_158_000
    }

    test "lays one request out as aligned columns under its time" do
      assert Usage.card([@entry]) ==
               """
               22:15:58 UTC
               input    4,930   cached     4,000
               output     132   reasoning    640
               cost    $0.003   estimated at list prices\
               """
    end

    test "opens with the request count and time span for several entries" do
      second = %{@entry | "at" => 1_700_000_167_000, "input_tokens" => 5_070}

      assert Usage.card([@entry, second]) |> String.split("\n") |> hd() ==
               "2 requests · 22:15:58 – 22:16:07 UTC"
    end

    test "counts missing counters as zero" do
      card = Usage.card([%{"input_tokens" => 12, "at" => 1_700_000_158_000}])

      assert card =~ "input       12   cached         0"
      assert card =~ "output       0   reasoning      0"
    end

    test "shows a dash and no note when no entry carries a cost" do
      card = Usage.card([Map.delete(@entry, "total_cost")])

      assert card |> String.split("\n") |> List.last() == "cost         —"
    end
  end
end
