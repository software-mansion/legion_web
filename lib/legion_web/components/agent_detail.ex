defmodule LegionWeb.Components.AgentDetail do
  @moduledoc false

  use LegionWeb, :html

  alias LegionWeb.Components.{Chat, Trace, Usage}
  alias LegionWeb.Helpers

  attr :agent, :map, default: nil
  attr :trace_items, :list, default: []
  attr :system_prompt, :string, default: nil
  attr :show_prompt_modal, :boolean, default: false
  attr :agent_config, :map, default: %{}
  attr :code_language, :string, default: nil
  attr :chat_form, :any, required: true
  attr :prefix, :string, required: true
  attr :usage, :list, default: []

  def render(%{agent: nil} = assigns) do
    ~H"""
    <div class="flex-1 flex items-center justify-center">
      <div class="text-center">
        <div class="w-10 h-10 rounded-xl bg-sol-base2 flex items-center justify-center mx-auto mb-3">
          <span class="text-sol-base1 text-lg">&larr;</span>
        </div>
        <p class="text-sm text-sol-base1">Select an agent to inspect</p>
      </div>
    </div>
    """
  end

  def render(assigns) do
    is_subagent = assigns.agent.parent_agent_id != nil
    assigns = assign(assigns, :is_subagent, is_subagent)

    ~H"""
    <div class="flex-1 flex flex-col overflow-hidden relative">
      <%!-- Header --%>
      <div class="px-6 py-4 border-b border-sol-base2 shrink-0 bg-sol-base2/50">
        <div :if={@is_subagent} class="flex items-center gap-1.5 mb-2">
          <.link
            patch={"#{@prefix}/#{Helpers.encode_agent_id(@agent.parent_agent_id)}"}
            class="text-xs text-sol-violet hover:text-sol-violet/80 transition-colors"
          >
            &larr; parent agent
          </.link>
          <span class="text-sol-base1 text-xs">/</span>
          <span class="text-xs text-sol-base00">{Helpers.module_name(@agent.agent_module)}</span>
        </div>
        <div class="flex items-center gap-3">
          <span class={["w-2.5 h-2.5 rounded-full shrink-0", Helpers.status_class(@agent.status)]}></span>
          <h2 class="text-base font-semibold text-sol-base02 tracking-tight">
            {Helpers.module_name(@agent.agent_module)}
          </h2>
          <span class={[
            "text-[10px] font-medium uppercase tracking-wider px-2 py-0.5 rounded-full",
            status_badge_class(@agent.status)
          ]}>
            {Helpers.status_label(@agent.status)}
          </span>
          <.identity_chip identity={@agent.identity} />
          <div class="ml-auto flex items-center gap-4 text-xs text-sol-base00">
            <button
              :if={@system_prompt}
              phx-click="show_prompt"
              class="text-sol-violet hover:text-sol-violet/80 transition-colors cursor-pointer"
            >
              System Prompt
            </button>
            <Usage.summary usage={@usage} />
            <span :if={duration = Helpers.format_duration(@agent.started_at, @agent.finished_at)}>
              {duration}
            </span>
            <span>{Helpers.relative_time(@agent.started_at)}</span>
          </div>
        </div>
      </div>

      <%!-- Trace --%>
      <Trace.render items={@trace_items} language={@code_language} />

      <%!-- Chat --%>
      <Chat.render
        :if={@agent.pid && @agent.status in [:running, :idle, :waiting_for_human, :done]}
        status={@agent.status}
        form={@chat_form}
      />

      <%!-- System Prompt Overlay --%>
      <div
        :if={@show_prompt_modal && @system_prompt}
        class="absolute inset-0 z-10 flex flex-col bg-sol-base3"
        phx-window-keydown="close_prompt"
        phx-key="Escape"
      >
        <div class="flex items-start justify-between gap-3 px-6 py-4 border-b border-sol-base2 shrink-0">
          <div class="flex items-center gap-3 flex-wrap min-w-0">
            <h3 class="text-sm font-semibold text-sol-base02">System Prompt</h3>
            <span
              :for={{key, val} <- @agent_config}
              class="text-[10px] px-2 py-0.5 rounded-full bg-sol-base2 text-sol-base00 whitespace-nowrap"
            >
              {key}: {format_config_value(val)}
            </span>
          </div>
          <button
            phx-click="close_prompt"
            class="w-7 h-7 flex items-center justify-center rounded text-sol-base1 hover:text-sol-base01 hover:bg-sol-base2 transition-colors cursor-pointer"
          >
            &times;
          </button>
        </div>
        <div class="flex-1 overflow-y-auto px-6 pt-3 pb-6">
          <div class="prompt-prose max-w-3xl">{@system_prompt}</div>
        </div>
      </div>
    </div>
    """
  end

  attr :identity, :map, default: nil

  @doc """
  Header chip for the agent's rate-limit identity.

  Shows one `key: value` pair and a `+N` count when more follow; hovering or
  focusing the chip lists the rest in a note. Which pair leads is the
  identity's map order, which is unspecified. Renders nothing for `nil` or an
  empty identity.
  """
  def identity_chip(%{identity: identity} = assigns)
      when is_nil(identity) or map_size(identity) == 0 do
    ~H""
  end

  def identity_chip(assigns) do
    [{key, val} | rest] = Enum.to_list(assigns.identity)
    assigns = assign(assigns, key: key, val: val, rest: rest)

    ~H"""
    <span
      title={@rest == [] && "Rate-limit identity"}
      class={[
        "inline-flex items-center gap-1.5 text-[10px] px-2 py-0.5 rounded-full whitespace-nowrap",
        "border border-sol-base1/45 bg-sol-base3 text-sol-base00 hover:bg-sol-base2 transition-colors",
        @rest != [] && "note note-left cursor-help"
      ]}
      data-note={
        @rest != [] && Enum.map_join(@rest, "\n", fn {k, v} -> "#{k}: #{format_config_value(v)}" end)
      }
      tabindex={@rest != [] && "0"}
    >
      {@key}: {format_config_value(@val)}
      <span
        :if={@rest != []}
        class="font-mono text-[9px] px-1 rounded-full text-sol-violet bg-sol-violet/10"
      >
        +{length(@rest)}
      </span>
    </span>
    """
  end

  defp format_config_value({provider, model, _options})
       when (is_atom(provider) or is_binary(provider)) and (is_atom(model) or is_binary(model)),
       do: "#{provider}/#{model}"

  defp format_config_value({provider, model})
       when (is_atom(provider) or is_binary(provider)) and (is_atom(model) or is_binary(model)),
       do: "#{provider}/#{model}"

  defp format_config_value(value) when is_binary(value) or is_atom(value) or is_number(value),
    do: value

  defp format_config_value(value), do: inspect(value)

  defp status_badge_class(:running), do: "bg-sol-green/15 text-sol-green"
  defp status_badge_class(:idle), do: "bg-sol-blue/15 text-sol-blue"
  defp status_badge_class(:waiting_for_human), do: "bg-sol-yellow/15 text-sol-yellow"
  defp status_badge_class(:done), do: "bg-sol-cyan/15 text-sol-cyan"
  defp status_badge_class(:error), do: "bg-sol-red/15 text-sol-red"
  defp status_badge_class(:dead), do: "bg-sol-red/15 text-sol-red"
  defp status_badge_class(_), do: "bg-sol-base1/15 text-sol-base1"
end
