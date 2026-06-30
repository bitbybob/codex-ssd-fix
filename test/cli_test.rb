# frozen_string_literal: true

require "stringio"
require "minitest/autorun"
require "codex_ssd_fix/cli"

class CLITest < Minitest::Test
  def test_help_exits_successfully_and_lists_commands
    stdout = StringIO.new
    stderr = StringIO.new

    status = CodexSsdFix::CLI.new(stdout: stdout, stderr: stderr).run(["help"])

    assert_equal 0, status
    assert_empty stderr.string
    assert_includes stdout.string, "guard"
    assert_includes stdout.string, "ramdisk"
    assert_includes stdout.string, "env"
    assert_includes stdout.string, "doctor"
  end

  def test_unknown_command_exits_nonzero_and_prints_concise_error
    stdout = StringIO.new
    stderr = StringIO.new

    status = CodexSsdFix::CLI.new(stdout: stdout, stderr: stderr).run(["nope"])

    refute_equal 0, status
    assert_empty stdout.string
    assert_equal "unknown command: nope\nrun `codex-ssd-fix help` for usage\n", stderr.string
  end

  def test_ramdisk_mount_rejects_invalid_size_before_implementation_runs
    stdout = StringIO.new
    stderr = StringIO.new

    status = CodexSsdFix::CLI.new(stdout: stdout, stderr: stderr).run(
      ["ramdisk", "mount", "--size-gib", "2.5"]
    )

    assert_equal 1, status
    assert_empty stdout.string
    assert_equal "size-gib must be a positive integer\n", stderr.string
  end

  def test_ramdisk_mount_accepts_default_model_options
    stdout = StringIO.new
    stderr = StringIO.new

    status = CodexSsdFix::CLI.new(stdout: stdout, stderr: stderr).run(["ramdisk", "status"])

    assert_equal 0, status
    assert_empty stderr.string
    assert_equal "ramdisk status: not implemented yet\n", stdout.string
  end

  def test_ramdisk_mount_rejects_missing_size_value
    stdout = StringIO.new
    stderr = StringIO.new

    status = CodexSsdFix::CLI.new(stdout: stdout, stderr: stderr).run(
      ["ramdisk", "mount", "--size-gib"]
    )

    assert_equal 1, status
    assert_empty stdout.string
    assert_equal "size-gib must be a positive integer\n", stderr.string
  end
end
