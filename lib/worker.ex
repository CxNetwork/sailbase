defmodule Sailbase.Worker do
  use GenServer
  require Logger

  alias Sailbase.Discovery

  def start_link do
    init_state = %{node_cached: false, notify_targets: MapSet.new()}
    GenServer.start_link(__MODULE__, init_state, name: __MODULE__)
  end

  def init(state) do
    if !Node.alive? do
      warn("Local node is not alive, will not search for cluster")
      :ignore
    else
      {:noreply, state} = handle_info(:update, state)
      info("Cluster controller initialisation for node: #{Node.self()}")
      {:ok, state}
    end
  end

  defp schedule do
    Process.send_after(self(), :update, 1500)
  end

  def handle_call(:wait_ready, from, state) do
    if state.node_cached do
      {:reply, :ok, state}
    else
      notify_targets =
        state.notify_targets
        |> MapSet.put(from)

      warn("Cordoning #{from} while nodes are being discovered")
      state = %{state | notify_targets: notify_targets}
      {:noreply, state}
    end
  end

  def handle_info(:update, state) do
    connect_to = Discovery.get_nodes(selector())
    connected_nodes = MapSet.new(Node.list())

    connections =
      MapSet.difference(connect_to, connected_nodes)
      |> Enum.map(& {&1, Node.connect(&1)})

    ok_count = log(connections, true, & "Connected to node #{&1}")
    log(connections, false, & "Failed to connect to node #{&1}", &warn/1)

    notify_targets = state.notify_targets
    state =
      if ok_count > 0 && !state.node_cached do
        count =
          notify_targets
          |> MapSet.to_list()
          |> notify_ready()

        info("Notified #{count} ex-processes that state is ready")
        %{node_cached: true, notify_targets: []}
      else
        state
      end

    disconnected_nodes =
      MapSet.difference(connected_nodes, connect_to)
      |> Enum.map(& {&1, Node.disconnect(&1)})

    log(disconnected_nodes, true, & "Disconnected from dead node #{&1}")
    log(disconnected_nodes, false, & "Disconnect from dead node failed #{&1}", &warn/1)

    schedule()
    {:noreply, state}
  end

  defp selector() do
    Application.get_env(:sailbase, :selector)
  end

  defp notify_ready([]), do: 0
  defp notify_ready([target | targets]) do
    GenServer.reply(target, :ok)
    1 + notify_ready(targets)
  end

  defp log(nodes, status, formatter, logger \\ &info/1)
  defp log([], _, _, _), do: 0
  defp log([conn | rest], status, formatter, logger) do
    log(conn, status, formatter, logger) + log(rest, status, formatter, logger)
  end
  defp log({node, status}, target_status, formatter, logger) do
    if status == target_status do
      logger.(formatter.(node))
      1
    else
      0
    end
  end

  defp info(msg, prefix \\ "[sailbase]"), do: do_logging(msg, prefix, &Logger.info/1)
  defp warn(msg, prefix \\ "[sailbase]"), do: do_logging(msg, prefix, &Logger.warn/1)
  defp do_logging(msg, prefix, to) do
    to.("#{prefix} #{msg}")
  end
end
