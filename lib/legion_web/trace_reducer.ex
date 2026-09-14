defmodule LegionWeb.TraceReducer do
  @moduledoc """
  Incrementally transforms raw telemetry events into typed display items.

  Handles event pairing (llm_stop + eval_stop), filtering of internal events,
  sub-agent grouping, and collapsing of redundant eval_and_complete + return/done pairs.

  ## Item types

    * `{:message, data}` - user message to the agent
    * `{:human_response, data}` - user response to HumanTool.ask
    * `{:exception, data}` - fatal error during message handling
    * `{:step, data}` - one LLM decision, optionally paired with eval outcome; `usage`
      lists the LLM usage entries behind it (two when an eval_and_complete + return
      pair is collapsed, none when the tracker recorded no usage)
    * `{:eval_error, data}` - standalone eval failure (unmatched with llm_stop)
    * `{:subagent, name, items}` - collapsible group of sub-agent events
    * `{:unknown, data}` - unrecognized event type
  """

  defstruct items: [],
            pending: nil,
            between: [],
            subagents: %{}

  @hidden_types ~w(iteration_start iteration_stop eval_start llm_start message_stop)a

  def new, do: %__MODULE__{}

  @doc "Returns the resolved list of display items."
  def items(%__MODULE__{} = state) do
    state
    |> flush_pending()
    |> resolve_subagents()
  end

  @doc "Process a single raw event, returning updated state."
  def push(%__MODULE__{} = state, %{type: type}) when type in @hidden_types, do: state

  def push(%__MODULE__{} = state, event) do
    if subagent_event?(event) do
      add_to_subagent(state, event)
    else
      process(state, event)
    end
  end

  # Sub-agent routing - classify and group, no pairing

  defp add_to_subagent(state, %{type: :eval_stop, data: %{success: true}}), do: state

  defp add_to_subagent(state, event) do
    key = event.data[:agent_id]
    name = agent_short_name(event.data[:agent])
    item = classify(event)

    if Map.has_key?(state.subagents, key) do
      subagents = Map.update!(state.subagents, key, fn {n, items} -> {n, [item | items]} end)
      %{state | subagents: subagents}
    else
      subagents = Map.put(state.subagents, key, {name, [item]})
      %{state | items: [{:subagent_placeholder, key} | state.items], subagents: subagents}
    end
  end

  # Main event processing - three-state machine:
  #   nil                          - normal processing
  #   {:awaiting_eval, llm_event}  - waiting for eval_stop to pair
  #   {:maybe_collapse, step}      - eval_and_complete step waiting for return/done

  # --- pending = nil ---

  defp process(
         %{pending: nil} = state,
         %{type: :llm_stop, data: %{object: %{"action" => action}}} = event
       )
       when action in ~w(eval_and_continue eval_and_complete) do
    %{state | pending: {:awaiting_eval, event}, between: []}
  end

  defp process(%{pending: nil} = state, %{type: :eval_stop, data: %{success: true}}), do: state

  defp process(%{pending: nil} = state, %{type: :eval_stop} = event) do
    append(state, build_eval_error(event))
  end

  defp process(%{pending: nil} = state, event) do
    append(state, classify(event))
  end

  # --- pending = {:awaiting_eval, llm_event} ---

  defp process(%{pending: {:awaiting_eval, llm_event}} = state, %{type: :eval_stop} = event) do
    step = build_step(llm_event, event)
    between_items = Enum.map(state.between, &classify/1)

    if llm_event.data.object["action"] == "eval_and_complete" do
      %{
        state
        | items: Enum.reverse(between_items) ++ state.items,
          pending: {:maybe_collapse, step},
          between: []
      }
    else
      %{
        state
        | items: Enum.reverse(between_items, [step | state.items]),
          pending: nil,
          between: []
      }
    end
  end

  defp process(%{pending: {:awaiting_eval, _}} = state, %{type: :llm_stop} = event) do
    state |> flush_pending() |> process(event)
  end

  defp process(%{pending: {:awaiting_eval, _}} = state, event) do
    %{state | between: [event | state.between]}
  end

  # --- pending = {:maybe_collapse, complete_step} ---

  defp process(
         %{pending: {:maybe_collapse, {:step, complete_data}}} = state,
         %{type: :llm_stop, data: %{object: %{"action" => action}}} = event
       )
       when action in ~w(return done) do
    {:step, return_data} = build_step(event, nil)

    merged =
      {:step,
       %{return_data | eval: complete_data.eval, usage: complete_data.usage ++ return_data.usage}}

    %{state | items: [merged | state.items], pending: nil, between: []}
  end

  defp process(%{pending: {:maybe_collapse, _}} = state, event) do
    state |> flush_pending() |> process(event)
  end

  # Flush pending state into items

  defp flush_pending(%{pending: nil} = state), do: state

  defp flush_pending(%{pending: {:awaiting_eval, llm_event}, between: between} = state) do
    step = build_step(llm_event, nil)
    between_items = Enum.map(between, &classify/1)
    %{state | items: Enum.reverse(between_items, [step | state.items]), pending: nil, between: []}
  end

  defp flush_pending(%{pending: {:maybe_collapse, step}} = state) do
    %{state | items: [step | state.items], pending: nil, between: []}
  end

  # Item builders

  defp classify(%{type: :message_start} = e) do
    {:message, %{seq: e.seq, ts: e.timestamp, text: e.data[:message]}}
  end

  defp classify(%{type: :human_response} = e) do
    {:human_response, %{seq: e.seq, ts: e.timestamp, text: e.data[:text]}}
  end

  defp classify(%{type: :message_exception} = e) do
    {:exception, %{seq: e.seq, ts: e.timestamp, reason: e.data[:reason]}}
  end

  defp classify(%{type: :llm_stop} = e), do: build_step(e, nil)

  defp classify(%{type: :eval_stop, data: %{success: false}} = e), do: build_eval_error(e)

  defp classify(e) do
    {:unknown, %{seq: e.seq, ts: e.timestamp, type: e.type}}
  end

  defp build_step(llm_event, eval_event) do
    object = llm_event.data[:object] || %{}

    eval =
      if eval_event do
        %{
          success: eval_event.data[:success],
          result: eval_event.data[:result],
          error: eval_event.data[:error],
          duration: eval_event.data[:duration]
        }
      end

    {:step,
     %{
       seq: llm_event.seq,
       ts: llm_event.timestamp,
       action: object["action"],
       code: object["code"],
       result: object["result"],
       error: llm_event.data[:error],
       duration: llm_event.data[:duration],
       eval: eval,
       usage: List.wrap(llm_event.data[:usage])
     }}
  end

  defp build_eval_error(event) do
    {:eval_error,
     %{
       seq: event.seq,
       ts: event.timestamp,
       error: event.data[:error],
       is_timeout: match?(%{type: :timeout}, event.data[:error])
     }}
  end

  defp append(state, item), do: %{state | items: [item | state.items]}

  defp resolve_subagents(%{items: items, subagents: subagents}) do
    items
    |> Enum.reverse()
    |> Enum.map(fn
      {:subagent_placeholder, key} ->
        {name, sub_items} = Map.fetch!(subagents, key)
        {:subagent, name, Enum.reverse(sub_items)}

      item ->
        item
    end)
  end

  defp subagent_event?(%{agent_id: agent_id, data: %{agent_id: data_agent_id}})
       when agent_id != data_agent_id,
       do: true

  defp subagent_event?(_), do: false

  defp agent_short_name(nil), do: "sub-agent"
  defp agent_short_name(module) when is_atom(module), do: module |> Module.split() |> List.last()
  defp agent_short_name(other), do: inspect(other)
end
