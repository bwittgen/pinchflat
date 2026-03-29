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
  end
end
