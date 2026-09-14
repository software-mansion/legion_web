defmodule LegionWeb.DashboardLiveTest do
  use ExUnit.Case, async: false

  alias LegionWeb.AgentTracker.{LegionAgent, Telemetry}
  alias LegionWeb.{DashboardLive, TraceReducer}
  alias Phoenix.LiveView.Socket

  defmodule FakeTool do
    def name, do: :fake
  end

  defmodule OtherTool do
    def name, do: :other
  end

  defmodule FakeAgent do
    def system_prompt, do: "# Agent\n\nhello\n\n```lua\nlocal x = 1\n```"
    def tools, do: [FakeTool, OtherTool]
    def tool_config(FakeTool), do: [timeout: 5_000]
    def tool_config(OtherTool), do: [retries: 3]
    def config, do: %{max_iterations: 7}
  end

  defmodule ConfiguredTracker do
    def list_agents(_limit), do: [%{agent_id: "configured", started_at: 1}]
    def get_agent(_agent_id), do: nil
    def get_events(_agent_id), do: []
    def get_usage(_agent_id), do: []
  end

  setup do
    :ets.delete_all_objects(:legion_web_agents)
    :ets.delete_all_objects(:legion_web_events)
    :ets.delete_all_objects(:legion_web_usage)
    Process.delete(:"$vault")
    Application.delete_env(:legion, :config)
    :ok
  end

  defp agent_record(agent_id, overrides \\ %{}) do
    struct(
      %LegionAgent{
        agent_id: agent_id,
        parent_agent_id: nil,
        agent_module: FakeAgent,
        pid: nil,
        status: :running,
        started_at: System.system_time(:millisecond),
        finished_at: nil,
        task: nil,
        iterations: 0
      },
      overrides
    )
  end

  defp empty_socket, do: %Socket{assigns: %{__changed__: %{}, flash: %{}}}

  defp tracker_session(overrides \\ %{}),
    do: Map.merge(%{"agent_tracker" => Telemetry}, overrides)

  defp mounted_socket(extra \\ %{}) do
    {:ok, socket} = DashboardLive.mount(%{}, tracker_session(), empty_socket())
    %{socket | assigns: Map.merge(socket.assigns, extra)}
  end

  describe "mount/3" do
    test "initializes empty state from session" do
      session = %{
        "prefix" => "/dashboard",
        "live_path" => "/live",
        "live_transport" => "longpoll",
        "csp_nonces" => %{img: "i", style: "s", script: "sc"}
      }

      {:ok, socket} = DashboardLive.mount(%{}, tracker_session(session), empty_socket())

      assert socket.assigns.prefix == "/dashboard"
      assert socket.assigns.live_path == "/live"
      assert socket.assigns.live_transport == "longpoll"
      assert socket.assigns.csp_nonces == %{img: "i", style: "s", script: "sc"}
      assert socket.assigns.agents == []
      assert socket.assigns.list_limit == DashboardLive.page_size()
      assert socket.assigns.selected_agent_id == nil
      assert socket.assigns.selected_agent == nil
      assert %TraceReducer{} = socket.assigns.trace
      assert socket.assigns.trace_items == []
      assert socket.assigns.system_prompt == nil
      assert socket.assigns.agent_config == %{}
      assert socket.assigns.show_prompt_modal == false
    end

    test "includes agents already tracked" do
      :ets.insert(:legion_web_agents, {"agent1", agent_record("agent1", %{started_at: 100})})
      :ets.insert(:legion_web_agents, {"agent2", agent_record("agent2", %{started_at: 200})})

      {:ok, socket} = DashboardLive.mount(%{}, tracker_session(), empty_socket())

      assert [%{agent_id: "agent2"}, %{agent_id: "agent1"}] = socket.assigns.agents
    end

    test "uses the tracker passed through the LiveView session" do
      {:ok, socket} =
        DashboardLive.mount(%{}, %{"agent_tracker" => ConfiguredTracker}, empty_socket())

      assert socket.assigns.agent_tracker == ConfiguredTracker
      assert socket.assigns.agents == [%{agent_id: "configured", started_at: 1}]
    end
  end

  describe "handle_params/3 without a agent_id" do
    test "clears selected agent state" do
      socket =
        mounted_socket(%{
          selected_agent_id: "old",
          selected_agent: agent_record("old"),
          trace_items: [{:message, %{text: "x"}}],
          system_prompt: "some prompt",
          agent_config: %{foo: :bar},
          code_language: "lua"
        })

      {:noreply, socket} = DashboardLive.handle_params(%{}, "/legion", socket)

      assert socket.assigns.selected_agent_id == nil
      assert socket.assigns.selected_agent == nil
      assert socket.assigns.trace_items == []
      assert socket.assigns.system_prompt == nil
      assert socket.assigns.agent_config == %{}
      assert socket.assigns.code_language == nil
    end
  end

  describe "handle_params/3 with a agent_id" do
    test "loads agent, replays events, and populates system_prompt/config" do
      agent_id = "demo"
      :ets.insert(:legion_web_agents, {agent_id, agent_record(agent_id)})

      :ets.insert(
        :legion_web_events,
        {{agent_id, 1},
         %{
           seq: 1,
           agent_id: agent_id,
           type: :message_start,
           timestamp: 1,
           data: %{agent_id: agent_id, message: "hello"}
         }}
      )

      Application.put_env(:legion, :config, %{env: :test})

      encoded = LegionWeb.Helpers.encode_agent_id(agent_id)

      {:noreply, socket} =
        DashboardLive.handle_params(%{"agent_id" => encoded}, "/legion", mounted_socket())

      assert socket.assigns.selected_agent_id == agent_id
      assert socket.assigns.selected_agent.agent_id == agent_id
      assert [{:message, %{text: "hello"}}] = socket.assigns.trace_items
      assert socket.assigns.agent_config == %{env: :test, max_iterations: 7}
      assert socket.assigns.system_prompt != nil
    end

    test "loads the agent's usage" do
      agent_id = "spender"
      :ets.insert(:legion_web_agents, {agent_id, agent_record(agent_id)})
      usage = %{"input_tokens" => 10, "output_tokens" => 2, "at" => 1}
      :ets.insert(:legion_web_usage, {{agent_id, 1}, usage})

      encoded = LegionWeb.Helpers.encode_agent_id(agent_id)

      {:noreply, socket} =
        DashboardLive.handle_params(%{"agent_id" => encoded}, "/legion", mounted_socket())

      assert socket.assigns.usage == [usage]
    end

    test "highlights fenced code in the system prompt by its fence language" do
      agent_id = "demo"
      :ets.insert(:legion_web_agents, {agent_id, agent_record(agent_id)})
      encoded = LegionWeb.Helpers.encode_agent_id(agent_id)

      {:noreply, socket} =
        DashboardLive.handle_params(%{"agent_id" => encoded}, "/legion", mounted_socket())

      {:safe, html} = socket.assigns.system_prompt
      html = IO.iodata_to_binary(html)
      assert html =~ ~s(<code class="language-lua highlight">)
      assert html =~ ~s(<span class="kd">local</span>)
    end

    test "derives code_language from the default sandbox when the agent sets none" do
      agent_id = "demo"
      :ets.insert(:legion_web_agents, {agent_id, agent_record(agent_id)})
      encoded = LegionWeb.Helpers.encode_agent_id(agent_id)

      {:noreply, socket} =
        DashboardLive.handle_params(%{"agent_id" => encoded}, "/legion", mounted_socket())

      assert socket.assigns.code_language == "lua"
    end

    test "derives code_language from the configured sandbox" do
      agent_id = "demo"
      :ets.insert(:legion_web_agents, {agent_id, agent_record(agent_id)})
      Application.put_env(:legion, :config, %{sandbox: Legion.Sandbox.Elixir})
      encoded = LegionWeb.Helpers.encode_agent_id(agent_id)

      {:noreply, socket} =
        DashboardLive.handle_params(%{"agent_id" => encoded}, "/legion", mounted_socket())

      assert socket.assigns.code_language == "elixir"
    end

    test "populates Vault with every tool's config before rendering the prompt" do
      agent_id = "vault_demo"
      :ets.insert(:legion_web_agents, {agent_id, agent_record(agent_id)})

      encoded = LegionWeb.Helpers.encode_agent_id(agent_id)

      {:noreply, _socket} =
        DashboardLive.handle_params(%{"agent_id" => encoded}, "/legion", mounted_socket())

      assert Vault.get(FakeTool) == [timeout: 5_000]
      assert Vault.get(OtherTool) == [retries: 3]
    end

    test "clears state when agent_id is unknown" do
      encoded = LegionWeb.Helpers.encode_agent_id("missing")

      {:noreply, socket} =
        DashboardLive.handle_params(%{"agent_id" => encoded}, "/legion", mounted_socket())

      assert socket.assigns.selected_agent_id == nil
      assert socket.assigns.selected_agent == nil
      assert socket.assigns.trace_items == []
      assert socket.assigns.system_prompt == nil
    end

    test "treats an invalid encoded agent_id as nil" do
      {:noreply, socket} =
        DashboardLive.handle_params(%{"agent_id" => "not-base64"}, "/legion", mounted_socket())

      assert socket.assigns.selected_agent_id == nil
      assert socket.assigns.selected_agent == nil
    end

    test "renders an agent whose module no longer exists without a prompt" do
      agent_id = "stale"

      :ets.insert(
        :legion_web_agents,
        {agent_id, agent_record(agent_id, %{agent_module: No.Such.Module})}
      )

      Application.put_env(:legion, :config, %{env: :test})
      encoded = LegionWeb.Helpers.encode_agent_id(agent_id)

      {:noreply, socket} =
        DashboardLive.handle_params(%{"agent_id" => encoded}, "/legion", mounted_socket())

      assert socket.assigns.selected_agent_id == agent_id
      assert socket.assigns.system_prompt == nil
      assert socket.assigns.agent_config == %{env: :test}
    end
  end

  describe "handle_info/2 - agent lifecycle" do
    test "adds a new agent on :started" do
      record = agent_record("agent1", %{started_at: 100})

      {:noreply, socket} =
        DashboardLive.handle_info({:started, "agent1", record}, mounted_socket())

      assert [%{agent_id: "agent1"}] = socket.assigns.agents
    end

    test "replaces existing agent with same agent_id" do
      existing = agent_record("agent1", %{started_at: 100, status: :running})
      socket = mounted_socket(%{agents: [existing]})

      updated = %{existing | status: :done}
      {:noreply, socket} = DashboardLive.handle_info({:stopped, "agent1", updated}, socket)

      assert [%{agent_id: "agent1", status: :done}] = socket.assigns.agents
    end

    test "sorts the list by started_at descending" do
      old = agent_record("old", %{started_at: 100})
      new = agent_record("new", %{started_at: 500})
      socket = mounted_socket(%{agents: [old]})

      {:noreply, socket} = DashboardLive.handle_info({:started, "new", new}, socket)

      assert [%{agent_id: "new"}, %{agent_id: "old"}] = socket.assigns.agents
    end

    test "updates selected_agent when the broadcast matches the current selection" do
      record = agent_record("agent1", %{status: :running})

      socket =
        mounted_socket(%{
          selected_agent_id: "agent1",
          selected_agent: record,
          agents: [record]
        })

      updated = %{record | status: :done}
      {:noreply, socket} = DashboardLive.handle_info({:stopped, "agent1", updated}, socket)

      assert socket.assigns.selected_agent.status == :done
    end

    test "leaves selected_agent untouched for a different agent_id" do
      selected = agent_record("agent1")
      other = agent_record("agent2")

      socket =
        mounted_socket(%{
          selected_agent_id: "agent1",
          selected_agent: selected,
          agents: [selected]
        })

      {:noreply, socket} = DashboardLive.handle_info({:started, "agent2", other}, socket)

      assert socket.assigns.selected_agent.agent_id == "agent1"
    end
  end

  describe "handle_info/2 - trace events" do
    test ":new_event pushes through the reducer and updates trace_items" do
      event = %{
        seq: 1,
        agent_id: "main",
        type: :message_start,
        timestamp: 1,
        data: %{agent_id: "main", message: "hi"}
      }

      {:noreply, socket} = DashboardLive.handle_info({:new_event, event}, mounted_socket())

      assert [{:message, %{text: "hi"}}] = socket.assigns.trace_items
    end
  end

  describe "handle_info/2 - usage" do
    test ":usage for the selected agent replaces the usage list" do
      socket = mounted_socket(%{selected_agent_id: "agent1", usage: []})
      usage = [%{"input_tokens" => 1, "at" => 1}]

      {:noreply, socket} = DashboardLive.handle_info({:usage, "agent1", usage}, socket)

      assert socket.assigns.usage == usage
    end

    test ":usage for another agent is ignored" do
      socket = mounted_socket(%{selected_agent_id: "agent1", usage: []})

      {:noreply, socket} =
        DashboardLive.handle_info({:usage, "agent2", [%{"input_tokens" => 1}]}, socket)

      assert socket.assigns.usage == []
    end

    test "a shorter :usage snapshot does not rewind the list" do
      fresh = [%{"at" => 1}, %{"at" => 2}, %{"at" => 3}]
      stale = [%{"at" => 1}, %{"at" => 2}]
      socket = mounted_socket(%{selected_agent_id: "agent1", usage: fresh})

      {:noreply, socket} = DashboardLive.handle_info({:usage, "agent1", stale}, socket)

      assert socket.assigns.usage == fresh
    end
  end

  describe "handle_info/2 - other messages" do
    test "unrecognized messages are ignored" do
      socket = mounted_socket()
      assert {:noreply, ^socket} = DashboardLive.handle_info(:anything, socket)
      assert {:noreply, ^socket} = DashboardLive.handle_info({:human_request, "sure?"}, socket)
    end
  end

  describe "handle_event/3 - prompt modal" do
    test "show_prompt opens the modal" do
      {:noreply, socket} = DashboardLive.handle_event("show_prompt", %{}, mounted_socket())
      assert socket.assigns.show_prompt_modal == true
    end

    test "close_prompt closes the modal" do
      socket = mounted_socket(%{show_prompt_modal: true})
      {:noreply, socket} = DashboardLive.handle_event("close_prompt", %{}, socket)
      assert socket.assigns.show_prompt_modal == false
    end
  end

  describe "handle_event/3 - pagination" do
    test "loads one page initially, then extends the loaded list by one page" do
      page_size = DashboardLive.page_size()

      for index <- 1..(page_size + 1) do
        agent_id = "agent-#{index}"
        :ets.insert(:legion_web_agents, {agent_id, agent_record(agent_id, %{started_at: index})})
      end

      socket = mounted_socket()

      assert length(socket.assigns.agents) == page_size
      assert socket.assigns.list_limit == page_size
      assert socket.assigns.has_more == true

      {:noreply, socket} = DashboardLive.handle_event("load_more", %{}, socket)

      assert length(socket.assigns.agents) == page_size + 1
      assert socket.assigns.list_limit == page_size * 2
      assert socket.assigns.has_more == false
    end

    test "has_more is false when the tracker holds exactly one page" do
      page_size = DashboardLive.page_size()

      for index <- 1..page_size do
        agent_id = "agent-#{index}"
        :ets.insert(:legion_web_agents, {agent_id, agent_record(agent_id, %{started_at: index})})
      end

      socket = mounted_socket()

      assert length(socket.assigns.agents) == page_size
      assert socket.assigns.has_more == false
    end
  end

  describe "handle_event/3 - send_message" do
    test "empty text is a no-op" do
      socket = mounted_socket()

      assert {:noreply, ^socket} =
               DashboardLive.handle_event("send_message", %{"chat" => %{"text" => ""}}, socket)
    end

    test "missing chat params is a no-op" do
      socket = mounted_socket()
      assert {:noreply, ^socket} = DashboardLive.handle_event("send_message", %{}, socket)
    end

    test "resets the chat form when no agent is selected" do
      socket = mounted_socket(%{selected_agent: nil})

      {:noreply, socket} =
        DashboardLive.handle_event("send_message", %{"chat" => %{"text" => "hi"}}, socket)

      assert %Phoenix.HTML.Form{} = socket.assigns.chat_form
      assert socket.assigns.chat_form.params == %{"text" => ""}
    end

    test "resets the chat form when the selected agent has a dead pid" do
      agent = agent_record("agent1", %{pid: spawn(fn -> :ok end)})
      Process.sleep(5)
      refute Process.alive?(agent.pid)

      socket = mounted_socket(%{selected_agent: agent})

      {:noreply, socket} =
        DashboardLive.handle_event("send_message", %{"chat" => %{"text" => "hi"}}, socket)

      assert socket.assigns.chat_form.params == %{"text" => ""}
    end
  end

  describe "AgentTracker integration" do
    test "mount reflects tracker state and handle_params loads agent by agent_id" do
      :ets.insert(:legion_web_agents, {"x", agent_record("x", %{started_at: 42})})

      {:ok, socket} = DashboardLive.mount(%{}, tracker_session(), empty_socket())
      assert Enum.any?(socket.assigns.agents, &(&1.agent_id == "x"))

      encoded = LegionWeb.Helpers.encode_agent_id("x")

      {:noreply, socket} =
        DashboardLive.handle_params(%{"agent_id" => encoded}, "/legion", socket)

      assert socket.assigns.selected_agent.agent_id == "x"
    end
  end
end
