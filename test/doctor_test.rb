# frozen_string_literal: true

require "minitest/autorun"
require "codex_ssd_fix/doctor"

class DoctorTest < Minitest::Test
  Result = Struct.new(:success?, keyword_init: true)

  class FakeRunner
    attr_reader :commands

    def initialize(found:)
      @found = found
      @commands = []
    end

    def run(argv)
      @commands << argv
      Result.new(success?: @found.fetch(argv.last, false))
    end
  end

  class FakeFilesystem
    def initialize(exists:, directory:, writable:)
      @exists = exists
      @directory = directory
      @writable = writable
    end

    def exist?(_path)
      @exists
    end

    def directory?(_path)
      @directory
    end

    def writable?(_path)
      @writable
    end
  end

  def test_doctor_output_when_all_dependencies_are_present
    runner = FakeRunner.new(
      found: {
        "sqlite3" => true,
        "hdiutil" => true,
        "diskutil" => true
      }
    )
    filesystem = FakeFilesystem.new(exists: true, directory: true, writable: true)

    result = CodexSsdFix::Doctor.new(
      runner: runner,
      platform: "arm64-darwin25",
      codex_home: "/Users/example/.codex",
      filesystem: filesystem
    ).run

    assert_equal 0, result.exit_status
    assert_includes result.output, "macos: supported"
    assert_includes result.output, "sqlite3: found"
    assert_includes result.output, "hdiutil: found"
    assert_includes result.output, "diskutil: found"
    assert_includes result.output, "codex home: writable (/Users/example/.codex)"
    assert_equal [
      ["/usr/bin/which", "sqlite3"],
      ["/usr/bin/which", "hdiutil"],
      ["/usr/bin/which", "diskutil"]
    ], runner.commands
  end

  def test_doctor_output_when_sqlite3_is_missing
    runner = FakeRunner.new(
      found: {
        "sqlite3" => false,
        "hdiutil" => true,
        "diskutil" => true
      }
    )
    filesystem = FakeFilesystem.new(exists: false, directory: false, writable: false)

    result = CodexSsdFix::Doctor.new(
      runner: runner,
      platform: "arm64-darwin25",
      codex_home: "/Users/example/.codex",
      filesystem: filesystem
    ).run

    assert_equal 1, result.exit_status
    assert_includes result.output, "sqlite3: missing"
    assert_includes result.output, "remediation: install sqlite3 or ensure it is available on PATH."
    assert_includes result.output, "codex home: not found (/Users/example/.codex)"
    assert_includes result.output, "write access not checked"
  end

  def test_non_macos_detection_message
    runner = FakeRunner.new(
      found: {
        "sqlite3" => true,
        "hdiutil" => true,
        "diskutil" => true
      }
    )
    filesystem = FakeFilesystem.new(exists: true, directory: true, writable: true)

    result = CodexSsdFix::Doctor.new(
      runner: runner,
      platform: "x86_64-linux",
      codex_home: "/home/example/.codex",
      filesystem: filesystem
    ).run

    assert_equal 1, result.exit_status
    assert_includes result.output, "macos: unsupported (x86_64-linux)"
    assert_includes result.output, "remediation: run this tool on macOS."
  end

  def test_existing_codex_home_must_be_writable
    runner = FakeRunner.new(
      found: {
        "sqlite3" => true,
        "hdiutil" => true,
        "diskutil" => true
      }
    )
    filesystem = FakeFilesystem.new(exists: true, directory: true, writable: false)

    result = CodexSsdFix::Doctor.new(
      runner: runner,
      platform: "arm64-darwin25",
      codex_home: "/Users/example/.codex",
      filesystem: filesystem
    ).run

    assert_equal 1, result.exit_status
    assert_includes result.output, "codex home: not writable (/Users/example/.codex)"
    assert_includes result.output, "remediation: fix directory permissions before applying guard changes."
  end
end
