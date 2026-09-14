defmodule LegionWeb.Components.UsageTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias LegionWeb.Components.Usage

  @usage [
    %{
      "input_tokens" => 1_800,
      "output_tokens" => 90,
      "cached_tokens" => 0,
      "total_cost" => 0.007,
      "at" => 0
    },
    %{
      "input_tokens" => 6_200,
      "output_tokens" => 1_150,
      "cached_tokens" => 3_300,
      "reasoning_tokens" => 380,
      "at" => 1
    }
  ]

  describe "summary/1" do
    test "renders input, output, cost and the totals card" do
      html = render_component(&Usage.summary/1, usage: @usage)

      assert html =~ "8.0k"
      assert html =~ "1.2k"
      assert html =~ "$0.007"
      assert html =~ "2 requests"
      assert html =~ "cached     3,300"
      assert html =~ "reasoning    380"
      assert html =~ "estimated at list prices"
    end

    test "renders nothing without usage" do
      assert render_component(&Usage.summary/1, usage: []) |> String.trim() == ""
    end
  end

  describe "chip/1" do
    @entry %{
      "input_tokens" => 4_930,
      "output_tokens" => 132,
      "cached_tokens" => 4_000,
      "reasoning_tokens" => 640,
      "total_cost" => 0.003,
      "at" => 1_700_000_158_000
    }

    test "renders tokens, cost and the request card" do
      html = render_component(&Usage.chip/1, usage: [@entry])

      assert html =~ "↑4.9k"
      assert html =~ "↓132"
      assert html =~ "$0.003"
      assert html =~ "22:15:58 UTC"
      assert html =~ "reasoning    640"
    end

    test "omits the cost when no entry carries one" do
      html = render_component(&Usage.chip/1, usage: [Map.delete(@entry, "total_cost")])

      assert html =~ "↑4.9k"
      refute html =~ "$"
    end

    test "sums several requests" do
      second = %{
        "input_tokens" => 5_070,
        "output_tokens" => 412,
        "total_cost" => 0.004,
        "at" => 1_700_000_167_000
      }

      html = render_component(&Usage.chip/1, usage: [@entry, second])

      assert html =~ "↑10.0k"
      assert html =~ "↓544"
      assert html =~ "$0.007"
      assert html =~ "2 requests · 22:15:58 – 22:16:07 UTC"
    end
  end
end
