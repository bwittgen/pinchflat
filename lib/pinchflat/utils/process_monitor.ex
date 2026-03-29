defmodule Pinchflat.Utils.ProcessMonitor do
  @moduledoc """
  Monitors subprocess execution with configurable timeout and memory limits.
  Terminates processes that exceed configured limits to prevent resource exhaustion
  from stuck yt-dlp or other child processes.
  """

  require Logger

  # How often to check process memory usage (in milliseconds)
  @memory_check_interval_ms 5_000

  @doc """
  Runs a command with timeout and memory monitoring.
  Behaves like `System.cmd/3` but adds timeout and memory limit enforcement.

  Supports the same core options as `System.cmd/3` (`:cd`, `:stderr_to_stdout`) plus:

    - `:timeout_ms` - max execution time in milliseconds (default from config, 0 to disable)
    - `:max_memory_kb` - max RSS memory in KB for process tree (default from config, 0 to disable)

  Returns `{output, exit_code}`
  """
  def run(command, args, opts \\ []) do
    {timeout_ms, opts} = Keyword.pop_lazy(opts, :timeout_ms, &default_timeout_ms/0)
    {max_memory_kb, cmd_opts} = Keyword.pop_lazy(opts, :max_memory_kb, &default_max_memory_kb/0)

    port_opts = build_port_opts(args, cmd_opts)
    port = Port.open({:spawn_executable, to_charlist(command)}, port_opts)

    os_pid =
      case Port.info(port, :os_pid) do
        {:os_pid, pid} -> pid
        _ -> nil
      end

    deadline = System.monotonic_time(:millisecond) + timeout_ms

    collect_output(port, os_pid, [], deadline, max_memory_kb)
  end

  # Collects output from a port with periodic timeout and memory checks.
  defp collect_output(port, os_pid, output_parts, deadline, max_memory_kb) do
    remaining_ms = deadline - System.monotonic_time(:millisecond)

    if remaining_ms <= 0 do
      Logger.error("[process_monitor] Process #{inspect(os_pid)} exceeded timeout limit, terminating")
      terminate_process(port, os_pid)
      {IO.iodata_to_binary(output_parts), 1}
    else
      wait_ms = min(@memory_check_interval_ms, max(remaining_ms, 1))

      receive do
        {^port, {:data, data}} ->
          collect_output(port, os_pid, [output_parts, data], deadline, max_memory_kb)

        {^port, {:exit_status, status}} ->
          {IO.iodata_to_binary(output_parts), status}
      after
        wait_ms ->
          if exceeds_memory_limit?(os_pid, max_memory_kb) do
            memory_kb = get_process_tree_memory_kb(os_pid)

            Logger.error(
              "[process_monitor] Process #{inspect(os_pid)} using #{memory_kb} KB, " <>
                "exceeds limit of #{max_memory_kb} KB, terminating"
            )

            terminate_process(port, os_pid)
            {IO.iodata_to_binary(output_parts), 1}
          else
            collect_output(port, os_pid, output_parts, deadline, max_memory_kb)
          end
      end
    end
  end

  defp build_port_opts(args, cmd_opts) do
    base = [
      :use_stdio,
      :exit_status,
      :binary,
      :hide,
      {:args, Enum.map(args, &to_charlist/1)}
    ]

    cd_opts =
      case Keyword.get(cmd_opts, :cd) do
        nil -> []
        dir -> [{:cd, to_charlist(dir)}]
      end

    stderr_opts =
      if Keyword.get(cmd_opts, :stderr_to_stdout, false) do
        [:stderr_to_stdout]
      else
        []
      end

    base ++ cd_opts ++ stderr_opts
  end

  defp terminate_process(port, os_pid) do
    if os_pid, do: kill_process_tree(os_pid)

    try do
      if Port.info(port) != nil, do: Port.close(port)
    catch
      _, _ -> :ok
    end

    drain_port_messages(port)
  end

  defp kill_process_tree(pid) do
    pid
    |> get_child_pids()
    |> Enum.each(&kill_process_tree/1)

    System.cmd("kill", ["-9", to_string(pid)], stderr_to_stdout: true)
  catch
    _, _ -> :ok
  end

  defp get_child_pids(parent_pid) do
    case File.read("/proc/#{parent_pid}/task/#{parent_pid}/children") do
      {:ok, content} ->
        content
        |> String.trim()
        |> String.split(" ", trim: true)
        |> Enum.map(&String.to_integer/1)

      _ ->
        try_pgrep(parent_pid)
    end
  end

  defp try_pgrep(parent_pid) do
    case System.cmd("pgrep", ["-P", to_string(parent_pid)], stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.trim()
        |> String.split("\n", trim: true)
        |> Enum.map(&String.to_integer/1)

      _ ->
        []
    end
  catch
    _, _ -> []
  end

  defp exceeds_memory_limit?(nil, _max_kb), do: false
  defp exceeds_memory_limit?(_pid, nil), do: false
  defp exceeds_memory_limit?(_pid, 0), do: false

  defp exceeds_memory_limit?(pid, max_kb) do
    get_process_tree_memory_kb(pid) > max_kb
  end

  defp get_process_tree_memory_kb(pid) do
    own_memory = get_process_memory_kb(pid)

    children_memory =
      pid
      |> get_child_pids()
      |> Enum.map(&get_process_tree_memory_kb/1)
      |> Enum.sum()

    own_memory + children_memory
  end

  defp get_process_memory_kb(pid) do
    case File.read("/proc/#{pid}/status") do
      {:ok, content} ->
        case Regex.run(~r/VmRSS:\s+(\d+)\s+kB/, content) do
          [_, kb_str] -> String.to_integer(kb_str)
          _ -> 0
        end

      _ ->
        0
    end
  end

  defp drain_port_messages(port) do
    receive do
      {^port, _} -> drain_port_messages(port)
    after
      0 -> :ok
    end
  end

  defp default_timeout_ms do
    seconds = Application.get_env(:pinchflat, :process_timeout_seconds, 1800)
    if seconds > 0, do: seconds * 1000, else: :timer.hours(24)
  end

  defp default_max_memory_kb do
    Application.get_env(:pinchflat, :max_process_memory_kb, 1_572_864)
  end
end
