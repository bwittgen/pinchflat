defmodule Pinchflat.Utils.ProcessMonitorTest do
  use Pinchflat.DataCase

  alias Pinchflat.Utils.ProcessMonitor

  describe "run/3" do
    test "runs a command and returns output and exit code" do
      assert {"hello\n", 0} = ProcessMonitor.run("/bin/echo", ["hello"])
    end

    test "returns the correct exit code on failure" do
      {_, exit_code} = ProcessMonitor.run("/bin/false", [])

      assert exit_code != 0
    end

    test "supports the cd option" do
      {output, 0} = ProcessMonitor.run("/bin/pwd", [], cd: "/tmp")

      assert String.trim(output) == "/tmp"
    end

    test "supports stderr_to_stdout option" do
      {output, _} = ProcessMonitor.run("/bin/sh", ["-c", "echo error >&2"], stderr_to_stdout: true)

      assert String.contains?(output, "error")
    end

    test "terminates processes that exceed timeout" do
      {_output, exit_code} = ProcessMonitor.run("/bin/sleep", ["60"], timeout_ms: 500)

      assert exit_code == 1
    end

    test "does not terminate processes within timeout" do
      {output, exit_code} = ProcessMonitor.run("/bin/echo", ["fast"], timeout_ms: 5_000)

      assert exit_code == 0
      assert String.trim(output) == "fast"
    end

    test "disables timeout when set to 0 via config" do
      original = Application.get_env(:pinchflat, :process_timeout_seconds)

      try do
        Application.put_env(:pinchflat, :process_timeout_seconds, 0)
        {output, exit_code} = ProcessMonitor.run("/bin/echo", ["works"])

        assert exit_code == 0
        assert String.trim(output) == "works"
      after
        Application.put_env(:pinchflat, :process_timeout_seconds, original)
      end
    end

    test "collects all output from the process" do
      {output, 0} = ProcessMonitor.run("/bin/sh", ["-c", "echo line1; echo line2; echo line3"])

      assert output == "line1\nline2\nline3\n"
    end

    @tag timeout: :timer.seconds(15)
    test "terminates processes that exceed memory limit" do
      # Any process uses well over 1 KB of RSS, so this triggers on the first memory check (~5s)
      {_output, exit_code} = ProcessMonitor.run("/bin/sleep", ["30"], max_memory_kb: 1, timeout_ms: 15_000)

      assert exit_code == 1
    end

    test "does not terminate processes within memory limit" do
      {output, exit_code} = ProcessMonitor.run("/bin/echo", ["ok"], max_memory_kb: 1_000_000, timeout_ms: 5_000)

      assert exit_code == 0
      assert String.trim(output) == "ok"
    end

    test "disables memory limit when set to 0 via option" do
      {output, exit_code} = ProcessMonitor.run("/bin/echo", ["works"], max_memory_kb: 0, timeout_ms: 5_000)

      assert exit_code == 0
      assert String.trim(output) == "works"
    end

    test "disables memory limit when set to 0 via config" do
      original = Application.get_env(:pinchflat, :max_process_memory_kb)

      try do
        Application.put_env(:pinchflat, :max_process_memory_kb, 0)
        {output, exit_code} = ProcessMonitor.run("/bin/echo", ["works"])

        assert exit_code == 0
        assert String.trim(output) == "works"
      after
        Application.put_env(:pinchflat, :max_process_memory_kb, original)
      end
    end
  end
end
