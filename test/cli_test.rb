# frozen_string_literal: true

require "stringio"
require "test_helper"
require "codex_ssd_fix/cli"
require "codex_ssd_fix/command_runner"

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

    assert_equal 2, status
    assert_empty stdout.string
    assert_equal "unknown command: nope\nrun `codex-ssd-fix help` for usage\n", stderr.string
  end

  def test_ramdisk_mount_rejects_invalid_size_before_implementation_runs
    stdout = StringIO.new
    stderr = StringIO.new

    status = CodexSsdFix::CLI.new(stdout: stdout, stderr: stderr).run(
      ["ramdisk", "mount", "--size-gib", "2.5"]
    )

    assert_equal 2, status
    assert_empty stdout.string
    assert_equal "size-gib must be a positive integer\n", stderr.string
  end

  def test_ramdisk_unknown_action_exits_usage_error
    stdout = StringIO.new
    stderr = StringIO.new

    status = CodexSsdFix::CLI.new(stdout: stdout, stderr: stderr).run(["ramdisk", "nope"])

    assert_equal 2, status
    assert_empty stdout.string
    assert_equal "invalid ramdisk action: nope\nusage: codex-ssd-fix ramdisk mount|status|unmount\n", stderr.string
  end

  def test_ramdisk_mount_rejects_missing_size_value
    stdout = StringIO.new
    stderr = StringIO.new

    status = CodexSsdFix::CLI.new(stdout: stdout, stderr: stderr).run(
      ["ramdisk", "mount", "--size-gib"]
    )

    assert_equal 2, status
    assert_empty stdout.string
    assert_equal "size-gib must be a positive integer\n", stderr.string
  end

  def test_env_rejects_invalid_mount_point_option
    stdout = StringIO.new
    stderr = StringIO.new

    status = CodexSsdFix::CLI.new(stdout: stdout, stderr: stderr).run(
      ["env", "--mount-point", " "]
    )

    assert_equal 2, status
    assert_empty stdout.string
    assert_equal "mount point must not be blank\n", stderr.string
  end

  def test_simulated_hdiutil_failure_exits_runtime_failure_with_concise_message
    stdout = StringIO.new
    stderr = StringIO.new
    runner = FailingRunBangRunner.new(stderr: "attach denied\n")

    status = CodexSsdFix::CLI.new(
      stdout: stdout,
      stderr: stderr,
      runner: runner,
      filesystem: FakeFilesystem.new(directory: false),
      fileutils: NullFileUtils.new
    ).run(["ramdisk", "mount"])

    assert_equal 1, status
    assert_empty stdout.string
    assert_equal "hdiutil failed with exit status 1: attach denied\n", stderr.string
    assert_equal [["hdiutil", "attach", "-nomount", "ram://4194304"]], runner.commands
  end

  class FailingRunBangRunner
    attr_reader :commands

    def initialize(stderr:)
      @stderr = stderr
      @commands = []
    end

    def run!(argv)
      @commands << argv
      result = CodexSsdFix::CommandRunner::Result.new(
        argv: argv,
        stdout: "",
        stderr: @stderr,
        exit_status: 1,
        elapsed_seconds: 0.0
      )
      raise CodexSsdFix::CommandRunner::Error, result
    end
  end

  class FakeFilesystem
    def initialize(directory:)
      @directory = directory
    end

    def directory?(_path)
      @directory
    end
  end

  class NullFileUtils
    def mkdir_p(_paths); end
  end
end
