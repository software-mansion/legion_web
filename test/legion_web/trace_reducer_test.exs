defmodule LegionWeb.TraceReducerTest do
  use ExUnit.Case, async: true

  alias LegionWeb.TraceReducer

  defp event(attrs) do
    Map.merge(
      %{seq: 1, agent_id: "main", timestamp: 1_000, data: %{agent_id: "main"}},
      attrs
    )
  end

  defp push_all(events) do
    Enum.reduce(events, TraceReducer.new(), &TraceReducer.push(&2, &1))
  end

  defp items(events), do: events |> push_all() |> TraceReducer.items()

  describe "new/0" do
    test "returns empty state" do
      state = TraceReducer.new()
      assert %TraceReducer{items: [], pending: nil, between: [], subagents: %{}} = state
    end

    test "items of empty state is empty list" do
      assert TraceReducer.items(TraceReducer.new()) == []
    end
  end

  describe "hidden events" do
    test "filters out iteration_start, iteration_stop, eval_start, llm_start, message_stop" do
      hidden_types = ~w(iteration_start iteration_stop eval_start llm_start message_stop)a

      for type <- hidden_types do
        result = items([event(%{type: type})])
        assert result == [], "expected #{type} to be hidden, got: #{inspect(result)}"
      end
    end
  end

  describe "classify - simple event types" do
    test "message_start becomes :message" do
      [item] =
        items([event(%{type: :message_start, data: %{agent_id: "main", message: "hello"}})])

      assert {:message, %{text: "hello", seq: 1, ts: 1_000}} = item
    end

    test "human_response becomes :human_response" do
      [item] = items([event(%{type: :human_response, data: %{agent_id: "main", text: "yes"}})])
      assert {:human_response, %{text: "yes"}} = item
    end

    test "message_exception becomes :exception" do
      [item] =
        items([
          event(%{type: :message_exception, data: %{agent_id: "main", reason: "timeout"}})
        ])

      assert {:exception, %{reason: "timeout"}} = item
    end

    test "unrecognized type becomes :unknown" do
      [item] = items([event(%{type: :something_weird, data: %{agent_id: "main"}})])
      assert {:unknown, %{type: :something_weird}} = item
    end
  end

  describe "LLM stop without eval pairing" do
    test "llm_stop with return action produces step without eval" do
      [item] =
        items([
          event(%{
            type: :llm_stop,
            data: %{
              agent_id: "main",
              object: %{"action" => "return", "code" => nil, "result" => "42"},
              duration: 100
            }
          })
        ])

      assert {:step, data} = item
      assert data.action == "return"
      assert data.result == "42"
      assert data.eval == nil
    end

    test "llm_stop with done action produces step without eval" do
      [item] =
        items([
          event(%{
            type: :llm_stop,
            data: %{agent_id: "main", object: %{"action" => "done"}, duration: 50}
          })
        ])

      assert {:step, %{action: "done", eval: nil}} = item
    end
  end

  describe "LLM stop error propagation" do
    test "llm_stop with error populates :error on step" do
      [item] =
        items([
          event(%{
            type: :llm_stop,
            data: %{
              agent_id: "main",
              object: %{},
              error: %{message: "rate limited"},
              duration: 10
            }
          })
        ])

      assert {:step, data} = item
      assert data.error == %{message: "rate limited"}
      assert data.action == nil
      assert data.result == nil
      assert data.eval == nil
    end

    test "llm_stop without error has :error as nil" do
      [item] =
        items([
          event(%{
            type: :llm_stop,
            data: %{agent_id: "main", object: %{"action" => "done"}, duration: 50}
          })
        ])

      assert {:step, %{error: nil}} = item
    end
  end

  describe "LLM stop + eval pairing (eval_and_continue)" do
    test "pairs llm_stop with following eval_stop" do
      [item] =
        items([
          event(%{
            seq: 1,
            type: :llm_stop,
            data: %{
              agent_id: "main",
              object: %{"action" => "eval_and_continue", "code" => "1+1"},
              duration: 100
            }
          }),
          event(%{
            seq: 2,
            type: :eval_stop,
            data: %{agent_id: "main", success: true, result: "2", error: nil, duration: 10}
          })
        ])

      assert {:step, data} = item
      assert data.action == "eval_and_continue"
      assert data.code == "1+1"
      assert data.eval.success == true
      assert data.eval.result == "2"
      assert data.eval.duration == 10
    end

    test "successful eval_stop without pending llm is dropped" do
      result = items([event(%{type: :eval_stop, data: %{agent_id: "main", success: true}})])
      assert result == []
    end

    test "failed eval_stop without pending llm becomes :eval_error" do
      [item] =
        items([
          event(%{
            type: :eval_stop,
            data: %{agent_id: "main", success: false, error: "boom", duration: 5}
          })
        ])

      assert {:eval_error, %{error: "boom", is_timeout: false}} = item
    end

    test "timeout eval_stop sets is_timeout flag" do
      [item] =
        items([
          event(%{
            type: :eval_stop,
            data: %{agent_id: "main", success: false, error: %{type: :timeout}, duration: 5000}
          })
        ])

      assert {:eval_error, %{is_timeout: true}} = item
    end
  end

  describe "eval_and_complete + return/done collapse" do
    test "collapses eval_and_complete step with following return into single step" do
      [item] =
        items([
          event(%{
            seq: 1,
            type: :llm_stop,
            data: %{
              agent_id: "main",
              object: %{"action" => "eval_and_complete", "code" => "result = 42"},
              duration: 100
            }
          }),
          event(%{
            seq: 2,
            type: :eval_stop,
            data: %{agent_id: "main", success: true, result: "42", error: nil, duration: 10}
          }),
          event(%{
            seq: 3,
            type: :llm_stop,
            data: %{
              agent_id: "main",
              object: %{"action" => "return", "result" => "42"},
              duration: 50
            }
          })
        ])

      assert {:step, data} = item
      assert data.action == "return"
      assert data.eval.success == true
      assert data.eval.result == "42"
    end

    test "collapses eval_and_complete step with following done" do
      [item] =
        items([
          event(%{
            seq: 1,
            type: :llm_stop,
            data: %{
              agent_id: "main",
              object: %{"action" => "eval_and_complete", "code" => "x = 1"},
              duration: 100
            }
          }),
          event(%{
            seq: 2,
            type: :eval_stop,
            data: %{agent_id: "main", success: true, result: "1", error: nil, duration: 10}
          }),
          event(%{
            seq: 3,
            type: :llm_stop,
            data: %{
              agent_id: "main",
              object: %{"action" => "done"},
              duration: 30
            }
          })
        ])

      assert {:step, data} = item
      assert data.action == "done"
      assert data.eval.success == true
    end

    test "when non-collapsible event follows eval_and_complete, flushes pending" do
      result =
        items([
          event(%{
            seq: 1,
            type: :llm_stop,
            data: %{
              agent_id: "main",
              object: %{"action" => "eval_and_complete", "code" => "x = 1"},
              duration: 100
            }
          }),
          event(%{
            seq: 2,
            type: :eval_stop,
            data: %{agent_id: "main", success: true, result: "1", error: nil, duration: 10}
          }),
          event(%{
            seq: 3,
            type: :message_start,
            data: %{agent_id: "main", message: "new message"}
          })
        ])

      assert [{:step, _}, {:message, _}] = result
    end
  end

  describe "between events during awaiting_eval" do
    test "events arriving between llm_stop and eval_stop are preserved" do
      result =
        items([
          event(%{
            seq: 1,
            type: :llm_stop,
            data: %{
              agent_id: "main",
              object: %{"action" => "eval_and_continue", "code" => "x = 1"},
              duration: 100
            }
          }),
          event(%{
            seq: 2,
            type: :message_start,
            data: %{agent_id: "main", message: "between event"}
          }),
          event(%{
            seq: 3,
            type: :eval_stop,
            data: %{agent_id: "main", success: true, result: "1", error: nil, duration: 10}
          })
        ])

      assert [{:step, _step}, {:message, %{text: "between event"}}] = result
    end

    test "new llm_stop while awaiting_eval flushes the pending step" do
      result =
        items([
          event(%{
            seq: 1,
            type: :llm_stop,
            data: %{
              agent_id: "main",
              object: %{"action" => "eval_and_continue", "code" => "first"},
              duration: 100
            }
          }),
          event(%{
            seq: 2,
            type: :llm_stop,
            data: %{
              agent_id: "main",
              object: %{"action" => "return", "result" => "done"},
              duration: 50
            }
          })
        ])

      assert [{:step, first}, {:step, second}] = result
      assert first.code == "first"
      assert first.eval == nil
      assert second.action == "return"
    end
  end

  describe "flush_pending on items/1" do
    test "flushes awaiting_eval state" do
      state =
        TraceReducer.new()
        |> TraceReducer.push(
          event(%{
            type: :llm_stop,
            data: %{
              agent_id: "main",
              object: %{"action" => "eval_and_continue", "code" => "pending"},
              duration: 100
            }
          })
        )

      result = TraceReducer.items(state)
      assert [{:step, %{code: "pending", eval: nil}}] = result
    end

    test "flushes maybe_collapse state" do
      state =
        TraceReducer.new()
        |> TraceReducer.push(
          event(%{
            seq: 1,
            type: :llm_stop,
            data: %{
              agent_id: "main",
              object: %{"action" => "eval_and_complete", "code" => "x"},
              duration: 100
            }
          })
        )
        |> TraceReducer.push(
          event(%{
            seq: 2,
            type: :eval_stop,
            data: %{agent_id: "main", success: true, result: "ok", error: nil, duration: 10}
          })
        )

      result = TraceReducer.items(state)
      assert [{:step, %{eval: %{success: true}}}] = result
    end
  end

  describe "sub-agent events" do
    test "events with mismatched agent_id are grouped as subagent" do
      result =
        items([
          event(%{
            seq: 1,
            type: :llm_stop,
            agent_id: "main",
            data: %{
              agent_id: "sub",
              agent: MyApp.SubAgent,
              object: %{"action" => "return", "result" => "sub result"},
              duration: 50
            }
          })
        ])

      assert [{:subagent, "SubAgent", sub_items}] = result
      assert [{:step, _}] = sub_items
    end

    test "multiple events for same sub-agent are grouped together" do
      result =
        items([
          event(%{
            seq: 1,
            type: :message_start,
            agent_id: "main",
            data: %{agent_id: "sub", agent: MyApp.Worker, message: "task"}
          }),
          event(%{
            seq: 2,
            type: :llm_stop,
            agent_id: "main",
            data: %{
              agent_id: "sub",
              agent: MyApp.Worker,
              object: %{"action" => "return", "result" => "done"},
              duration: 50
            }
          })
        ])

      assert [{:subagent, "Worker", sub_items}] = result
      assert length(sub_items) == 2
    end

    test "successful eval_stop from sub-agent is dropped" do
      result =
        items([
          event(%{
            seq: 1,
            type: :eval_stop,
            agent_id: "main",
            data: %{agent_id: "sub", agent: MyApp.Sub, success: true}
          })
        ])

      assert result == []
    end

    test "sub-agent with nil module shows 'sub-agent'" do
      result =
        items([
          event(%{
            seq: 1,
            type: :message_start,
            agent_id: "main",
            data: %{agent_id: "sub", agent: nil, message: "hi"}
          })
        ])

      assert [{:subagent, "sub-agent", _}] = result
    end

    test "sub-agent placeholder ordering is preserved" do
      result =
        items([
          event(%{
            seq: 1,
            type: :message_start,
            data: %{agent_id: "main", message: "first"}
          }),
          event(%{
            seq: 2,
            type: :message_start,
            agent_id: "main",
            data: %{agent_id: "sub1", agent: MyApp.A, message: "sub"}
          }),
          event(%{
            seq: 3,
            type: :message_start,
            data: %{agent_id: "main", message: "last"}
          })
        ])

      assert [{:message, %{text: "first"}}, {:subagent, "A", _}, {:message, %{text: "last"}}] =
               result
    end
  end

  describe "complex sequences" do
    test "multiple steps in sequence" do
      result =
        items([
          event(%{
            seq: 1,
            type: :llm_stop,
            data: %{
              agent_id: "main",
              object: %{"action" => "eval_and_continue", "code" => "step1"},
              duration: 100
            }
          }),
          event(%{
            seq: 2,
            type: :eval_stop,
            data: %{agent_id: "main", success: true, result: "r1", error: nil, duration: 10}
          }),
          event(%{
            seq: 3,
            type: :llm_stop,
            data: %{
              agent_id: "main",
              object: %{"action" => "eval_and_continue", "code" => "step2"},
              duration: 200
            }
          }),
          event(%{
            seq: 4,
            type: :eval_stop,
            data: %{agent_id: "main", success: false, result: nil, error: "fail", duration: 5}
          }),
          event(%{
            seq: 5,
            type: :llm_stop,
            data: %{
              agent_id: "main",
              object: %{"action" => "return", "result" => "final"},
              duration: 50
            }
          })
        ])

      assert [
               {:step, %{code: "step1", eval: %{success: true}}},
               {:step, %{code: "step2", eval: %{success: false}}},
               {:step, %{action: "return"}}
             ] = result
    end

    test "message then steps then exception" do
      result =
        items([
          event(%{
            seq: 1,
            type: :message_start,
            data: %{agent_id: "main", message: "do something"}
          }),
          event(%{
            seq: 2,
            type: :llm_stop,
            data: %{
              agent_id: "main",
              object: %{"action" => "eval_and_continue", "code" => "boom()"},
              duration: 100
            }
          }),
          event(%{
            seq: 3,
            type: :eval_stop,
            data: %{agent_id: "main", success: true, result: "ok", error: nil, duration: 10}
          }),
          event(%{
            seq: 4,
            type: :message_exception,
            data: %{agent_id: "main", reason: "crashed"}
          })
        ])

      assert [
               {:message, %{text: "do something"}},
               {:step, %{eval: %{success: true}}},
               {:exception, %{reason: "crashed"}}
             ] = result
    end
  end

  describe "usage" do
    @usage %{"input_tokens" => 10, "output_tokens" => 2, "at" => 1}

    test "a step carries its llm_stop usage as a one-entry list" do
      [item] =
        items([
          event(%{
            type: :llm_stop,
            data: %{agent_id: "main", object: %{"action" => "done"}, usage: @usage}
          })
        ])

      assert {:step, %{usage: [@usage]}} = item
    end

    test "a step without usage carries an empty list" do
      [item] =
        items([
          event(%{type: :llm_stop, data: %{agent_id: "main", object: %{"action" => "done"}}})
        ])

      assert {:step, %{usage: []}} = item
    end

    test "a step paired with its eval keeps its usage" do
      [item] =
        items([
          event(%{
            seq: 1,
            type: :llm_stop,
            data: %{
              agent_id: "main",
              object: %{"action" => "eval_and_continue", "code" => "x"},
              usage: @usage
            }
          }),
          event(%{
            seq: 2,
            type: :eval_stop,
            data: %{agent_id: "main", success: true, result: "ok"}
          })
        ])

      assert {:step, %{eval: %{success: true}, usage: [@usage]}} = item
    end

    test "a collapsed eval_and_complete + return step carries both requests in order" do
      complete = %{"input_tokens" => 10, "at" => 1}
      return = %{"input_tokens" => 20, "at" => 2}

      result =
        items([
          event(%{
            seq: 1,
            type: :llm_stop,
            data: %{
              agent_id: "main",
              object: %{"action" => "eval_and_complete", "code" => "x"},
              usage: complete
            }
          }),
          event(%{
            seq: 2,
            type: :eval_stop,
            data: %{agent_id: "main", success: true, result: "ok"}
          }),
          event(%{
            seq: 3,
            type: :llm_stop,
            data: %{
              agent_id: "main",
              object: %{"action" => "return", "result" => "final"},
              usage: return
            }
          })
        ])

      assert [{:step, %{action: "return", usage: [^complete, ^return]}}] = result
    end

    test "a collapsed step keeps only the request that carried usage" do
      return = %{"input_tokens" => 20, "at" => 2}

      result =
        items([
          event(%{
            seq: 1,
            type: :llm_stop,
            data: %{agent_id: "main", object: %{"action" => "eval_and_complete", "code" => "x"}}
          }),
          event(%{
            seq: 2,
            type: :eval_stop,
            data: %{agent_id: "main", success: true, result: "ok"}
          }),
          event(%{
            seq: 3,
            type: :llm_stop,
            data: %{
              agent_id: "main",
              object: %{"action" => "return", "result" => "final"},
              usage: return
            }
          })
        ])

      assert [{:step, %{usage: [^return]}}] = result
    end

    test "a sub-agent step carries its usage" do
      [{:subagent, _name, [item]}] =
        items([
          event(%{
            type: :llm_stop,
            data: %{agent_id: "child", object: %{"action" => "done"}, usage: @usage}
          })
        ])

      assert {:step, %{usage: [@usage]}} = item
    end
  end
end
