defmodule LegionWeb.Components.Usage do
  @moduledoc false

  use LegionWeb, :html

  alias LegionWeb.UsageAggregator, as: Usage

  attr :usage, :list, required: true

  @doc """
  Header summary: input / output tokens and estimated cost for the selected
  agent, with a card of conversation totals on hover.
  """
  def summary(assigns) do
    assigns = assign(assigns, :totals, Usage.totals(assigns.usage))

    ~H"""
    <span
      :if={@totals.requests > 0}
      class="note note-pre flex items-center gap-2 tabular-nums cursor-help"
      data-note={Usage.card(@usage)}
      tabindex="0"
    >
      <span>↑ {Usage.format_tokens(@totals.input)}</span>
      <span>↓ {Usage.format_tokens(@totals.output)}</span>
      <span
        :if={cost = Usage.format_cost(@totals.cost)}
        class="inline-flex items-center gap-1 px-1.5 py-0.5 rounded bg-sol-violet/10 text-sol-violet font-medium"
      >
        {cost}
        <span
          aria-hidden="true"
          class="inline-flex items-center justify-center w-3 h-3 rounded-full border border-current text-[8px] leading-none font-serif italic font-semibold opacity-75"
        >
          i
        </span>
      </span>
    </span>
    """
  end

  attr :usage, :list, required: true

  @doc """
  Trace step chip: input / output tokens and estimated cost of the step's LLM
  requests, with a per-request card on hover. The card opens upward so the
  bottom row of the trace is not clipped by its scroll container.
  """
  def chip(assigns) do
    assigns = assign(assigns, :totals, Usage.totals(assigns.usage))

    ~H"""
    <span
      class="note note-pre note-up inline-flex items-center gap-1.5 cursor-help"
      data-note={Usage.card(@usage)}
      tabindex="0"
    >
      <span>↑{Usage.format_tokens(@totals.input)}</span>
      <span>↓{Usage.format_tokens(@totals.output)}</span>
      <span :if={cost = Usage.format_cost(@totals.cost)} class="text-sol-violet font-medium">
        {cost}
      </span>
    </span>
    """
  end
end
