# frozen_string_literal: true

require "test_helper"
require "codex_ssd_fix/env_guide"

class EnvGuideTest < Minitest::Test
  def test_prints_shell_exports_for_mounted_ramdisk
    config = CodexSsdFix::Ramdisk.build
    guide = CodexSsdFix::EnvGuide.new(
      ramdisk: FakeRamdisk.new(
        CodexSsdFix::Ramdisk::StatusResult.new(
          config: config,
          mounted: true,
          scratch_paths: config.scratch_paths
        )
      )
    )

    result = guide.run

    assert_equal 0, result.exit_status
    assert_includes result.output, "export TMPDIR=/Volumes/CodexRAMFix/codex-scratch/tmp"
    assert_includes result.output, "export CODEX_ATTEMPT_ROOT=/Volumes/CodexRAMFix/codex-scratch/attempts"
    assert_includes result.output, "export CODEX_RUN_ROOT=/Volumes/CodexRAMFix/codex-scratch/generic"
    assert_includes result.output, "Keep CODEX_HOME on durable storage"
    refute_match(/^export CODEX_HOME=/, result.output)
  end

  def test_refuses_exports_when_ramdisk_is_not_mounted
    config = CodexSsdFix::Ramdisk.build
    guide = CodexSsdFix::EnvGuide.new(
      ramdisk: FakeRamdisk.new(
        CodexSsdFix::Ramdisk::StatusResult.new(
          config: config,
          mounted: false,
          scratch_paths: []
        )
      )
    )

    result = guide.run

    assert_equal 1, result.exit_status
    assert_equal "codex-ssd-fix ramdisk mount", result.output.lines.first.chomp
    refute_includes result.output, "export TMPDIR="
    refute_includes result.output, "/Volumes/CodexRAMFix/codex-scratch/tmp"
  end

  def test_not_mounted_command_preserves_custom_ramdisk_options
    config = CodexSsdFix::Ramdisk.build(
      size_gib: 4,
      name: "Codex Scratch",
      mount_point: "/Volumes/Codex Scratch"
    )
    guide = CodexSsdFix::EnvGuide.new(
      ramdisk: FakeRamdisk.new(
        CodexSsdFix::Ramdisk::StatusResult.new(
          config: config,
          mounted: false,
          scratch_paths: []
        )
      )
    )

    result = guide.run

    assert_equal "codex-ssd-fix ramdisk mount --size-gib 4 --name Codex\\ Scratch " \
                 "--mount-point /Volumes/Codex\\ Scratch",
                 result.output.lines.first.chomp
  end

  class FakeRamdisk
    def initialize(status)
      @status = status
    end

    def status
      @status
    end
  end
end
