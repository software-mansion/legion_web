# Changelog

## Unreleased

### Changes

- Inline usage - each trace step shows its LLM request's tokens and estimated cost, with a per-request hover card; the header pill's hover card carries the conversation totals. The `Usage` overlay is removed. Under the Postgres tracker, per-step usage needs Legion 0.6, which stamps usage entries with `"message_index"`

## v0.5.0 - 2026-09-01

### Changes

- Pluggable agent tracking - the [`LegionWeb.AgentTracker`](https://hexdocs.pm/legion_web/LegionWeb.AgentTracker.html) behaviour, [`LegionWeb.AgentTracker.Telemetry`](https://hexdocs.pm/legion_web/LegionWeb.AgentTracker.Telemetry.html) (default), [`LegionWeb.AgentTracker.Postgres`](https://hexdocs.pm/legion_web/LegionWeb.AgentTracker.Postgres.html) reading a [`Legion.Store.Postgres`](https://hexdocs.pm/legion/Legion.Store.Postgres.html) with live database notifications
- LLM usage - [`get_usage/1`](https://hexdocs.pm/legion_web/LegionWeb.AgentTracker.html#c:get_usage/1) tracker callback, tokens and estimated cost in the agent header, `Usage` overlay listing every request
- Syntax highlighting - [`LegionWeb.Markup`](https://hexdocs.pm/legion_web/LegionWeb.Markup.html) highlights trace code in the agent's [`Legion.Sandbox`](https://hexdocs.pm/legion/Legion.Sandbox.html) language (Lua by default) and system-prompt fences by language, via [makeup_syntect](https://hexdocs.pm/makeup_syntect)
- Agent identity - `agent_id` and `parent_agent_id` across records, routes, PubSub, and human-tool integration, matching Legion 0.5
- Markdown - styled trace responses, raw HTML escaped, malformed input rendered best-effort
- Pagination - agent list loads 20 agents at a time with a "Load more" button
- Hex package ships compiled assets (`priv/static/app.css`, `priv/static/app.js`)
- Fixes - [`:transport`](https://hexdocs.pm/legion_web/LegionWeb.Router.html#legion_dashboard/2) router option honored, cross-node agents via [`Legion.running?/1`](https://hexdocs.pm/legion/Legion.html#running?/1), persisted agents with a missing module, oldest-event eviction at the per-agent cap, pending HumanTool questions cleaned up on crash / timeout, telemetry handler survives tracker restarts, trace durations in native time units

## v0.3.0 - 2026-04-21

### Changes

- Introduce `TraceReducer` - incremental state machine that pairs LLM and eval events, groups sub-agent spans, and collapses redundant eval_and_complete + return/done pairs, replacing the previous multi-pass list processing in the Trace component
- Add system prompt overlay with agent config badges, accessible from the agent detail header
- Inline eval results directly into their parent LLM step instead of rendering separate rows
- Display final LLM response text and LLM errors in trace view
- Add `ResetForm` JS hook to clear chat input after submit
- Properly escape quoted strings when extracting `HumanTool.ask` questions
- Use Igniter module aliases in the install mix task
- Add tests for `DashboardLive`, `TraceReducer` error paths, and `legion_web.install` task

## v0.1.0

![LegionWeb Dashboard](https://raw.githubusercontent.com/dimamik/legion_web/main/img/preview.png)

Initial release of `legion_web` - stateless dashboard for monitoring your AI Agents spawned by legion.
