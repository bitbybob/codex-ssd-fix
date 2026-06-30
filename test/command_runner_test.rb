# frozen_string_literal: true

require "test_helper"
require "codex_ssd_fix/command_runner"

class CommandRunnerTest < Minitest::Test
  Status = Struct.new(:exitstatus)

  class FakeClock
    def initialize(*times)
      @times = times
    end

    def clock_gettime(_clock_id)
      @times.shift
    end
  end

  def test_successful_command_result_mapping
    runner = CodexSsdFix::CommandRunner.new(
      capture3: ->(_argv) { ["ok\n", "", Status.new(0)] },
      clock: FakeClock.new(10.0, 10.25)
    )

    result = runner.run(["printf", "ok"])

    assert result.success?
    assert_equal ["printf", "ok"], result.argv
    assert_equal "ok\n", result.stdout
    assert_equal "", result.stderr
    assert_equal 0, result.exit_status
    assert_in_delta 0.25, result.elapsed_seconds, 0.0001
  end

  def test_nonzero_command_result_and_error_message
    runner = CodexSsdFix::CommandRunner.new(
      capture3: ->(_argv) { ["", "missing file\n", Status.new(2)] },
      clock: FakeClock.new(4.0, 4.1, 5.0, 5.1)
    )

    result = runner.run(["sqlite3", "/tmp/missing.db"])

    refute result.success?
    assert_equal 2, result.exit_status
    assert_equal "sqlite3 failed with exit status 2: missing file", result.error_message

    error = assert_raises(CodexSsdFix::CommandRunner::Error) do
      runner.run!(["sqlite3", "/tmp/missing.db"])
    end
    assert_equal "sqlite3 failed with exit status 2: missing file", error.message
  end

  def test_error_message_uses_first_nonempty_stderr_line_only
    runner = CodexSsdFix::CommandRunner.new(
      capture3: ->(_argv) { ["", "\nfirst failure\nENV=secret\n", Status.new(1)] },
      clock: FakeClock.new(1.0, 1.0)
    )

    result = runner.run(["hdiutil", "attach"])

    assert_equal "hdiutil failed with exit status 1: first failure", result.error_message
  end

  def test_error_message_caps_long_stderr_line
    runner = CodexSsdFix::CommandRunner.new(
      capture3: ->(_argv) { ["", "#{"x" * 300}\n", Status.new(1)] },
      clock: FakeClock.new(1.0, 1.0)
    )

    result = runner.run(["hdiutil", "attach"])

    assert_equal 240, result.error_message.split(": ", 2).last.length
    assert result.error_message.end_with?("...")
  end

  def test_argv_array_preserves_paths_containing_spaces
    captured_argv = nil
    runner = CodexSsdFix::CommandRunner.new(
      capture3: lambda { |argv|
        captured_argv = argv
        ["", "", Status.new(0)]
      },
      clock: FakeClock.new(1.0, 1.0)
    )

    path = "/tmp/codex scratch/state db.sqlite3"
    runner.run(["sqlite3", path, "select 1;"])

    assert_equal ["sqlite3", path, "select 1;"], captured_argv
  end
end
