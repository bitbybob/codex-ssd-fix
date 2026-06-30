# frozen_string_literal: true

require "minitest/autorun"
require "codex_ssd_fix/ramdisk"

class RamdiskTest < Minitest::Test
  def test_default_model_uses_conservative_non_project_specific_mount_point
    config = CodexSsdFix::Ramdisk.build

    assert_equal 2, config.size_gib
    assert_equal "CodexRAMFix", config.name
    assert_equal "/Volumes/CodexRAMFix", config.mount_point
    assert_equal 4_194_304, config.sectors
    assert_equal "ram://4194304", config.ram_url
  end

  def test_two_gib_converts_to_hdiutil_sector_count
    config = CodexSsdFix::Ramdisk.build(size_gib: "2")

    assert_equal 4_194_304, config.sectors
    assert_equal ["hdiutil", "attach", "-nomount", "ram://4194304"], config.attach_command
  end

  def test_size_must_be_positive_integer
    ["0", "-1", "2.5", "abc", "", " 2"].each do |size|
      error = assert_raises(ArgumentError) do
        CodexSsdFix::Ramdisk.build(size_gib: size)
      end

      assert_equal "size-gib must be a positive integer", error.message
    end
  end

  def test_allows_name_and_mount_point_overrides
    config = CodexSsdFix::Ramdisk.build(
      size_gib: 1,
      name: "CodexScratch",
      mount_point: "/Volumes/CodexScratch"
    )

    assert_equal 1, config.size_gib
    assert_equal "CodexScratch", config.name
    assert_equal "/Volumes/CodexScratch", config.mount_point
    assert_equal 2_097_152, config.sectors
  end

  def test_blank_name_and_mount_point_are_rejected
    assert_raises(ArgumentError) { CodexSsdFix::Ramdisk.build(name: " ") }
    assert_raises(ArgumentError) { CodexSsdFix::Ramdisk.build(mount_point: " ") }
  end

  def test_mount_uses_argv_commands_and_creates_scratch_layout
    config = CodexSsdFix::Ramdisk.build(size_gib: "2")
    runner = RecordingRunner.new(stdout: "/dev/disk9\tApple_partition_scheme\n")
    filesystem = FakeFilesystem.new(directory: false)
    fileutils = RecordingFileUtils.new

    result = CodexSsdFix::Ramdisk.new(
      config: config,
      runner: runner,
      filesystem: filesystem,
      fileutils: fileutils
    ).mount

    assert result.mounted?
    assert_equal "/dev/disk9", result.device
    assert_equal [
      ["hdiutil", "attach", "-nomount", "ram://4194304"],
      ["diskutil", "erasevolume", "HFS+", "CodexRAMFix", "/dev/disk9"]
    ], runner.commands
    assert_equal [config.scratch_paths], fileutils.mkdir_p_calls
  end

  def test_mount_treats_existing_mount_path_idempotently
    config = CodexSsdFix::Ramdisk.build
    runner = RecordingRunner.new(stdout: "")
    filesystem = FakeFilesystem.new(directory: true)
    fileutils = RecordingFileUtils.new

    result = CodexSsdFix::Ramdisk.new(
      config: config,
      runner: runner,
      filesystem: filesystem,
      fileutils: fileutils
    ).mount

    refute result.mounted?
    assert_nil result.device
    assert_empty runner.commands
    assert_equal [config.scratch_paths], fileutils.mkdir_p_calls
  end

  def test_parse_device_handles_spaces_and_partition_suffixes
    output = "created disk image\n   /dev/disk12s1    Apple_HFS   CodexRAMFix\n"

    assert_equal "/dev/disk12s1", CodexSsdFix::Ramdisk.parse_device(output)
  end

  def test_parse_device_rejects_unrecognized_output
    error = assert_raises(CodexSsdFix::Ramdisk::Error) do
      CodexSsdFix::Ramdisk.parse_device("no device here")
    end

    assert_equal "could not parse RAM disk device from hdiutil output", error.message
  end

  def test_status_reports_mounted_and_scratch_paths_from_mount_and_df
    config = CodexSsdFix::Ramdisk.build
    runner = ScriptedRunner.new(
      ["mount"] => "/dev/disk9s1 on /Volumes/CodexRAMFix (hfs, local)\n",
      ["df", "-h"] => "Filesystem Size Used Avail Capacity Mounted on\n/dev/disk9s1 2.0Gi 1Mi 2.0Gi 1% /Volumes/CodexRAMFix\n"
    )

    result = CodexSsdFix::Ramdisk.new(config: config, runner: runner).status

    assert result.mounted?
    assert_equal config.scratch_paths, result.scratch_paths
    assert_equal [["mount"], ["df", "-h"]], runner.commands
  end

  def test_status_reports_not_mounted_when_outputs_do_not_include_mount_point
    config = CodexSsdFix::Ramdisk.build
    runner = ScriptedRunner.new(
      ["mount"] => "/dev/disk1s1 on / (apfs, local)\n",
      ["df", "-h"] => "Filesystem Size Used Avail Capacity Mounted on\n/dev/disk1s1 100Gi 50Gi 50Gi 50% /\n"
    )

    result = CodexSsdFix::Ramdisk.new(config: config, runner: runner).status

    refute result.mounted?
    assert_empty result.scratch_paths
  end

  def test_unmount_ejects_mount_point_when_mounted
    config = CodexSsdFix::Ramdisk.build
    runner = ScriptedRunner.new(
      ["mount"] => "/dev/disk9s1 on /Volumes/CodexRAMFix (hfs, local)\n",
      ["df", "-h"] => "Filesystem Size Used Avail Capacity Mounted on\n/dev/disk9s1 2.0Gi 1Mi 2.0Gi 1% /Volumes/CodexRAMFix\n",
      ["diskutil", "eject", "/Volumes/CodexRAMFix"] => "Disk ejected\n"
    )

    result = CodexSsdFix::Ramdisk.new(config: config, runner: runner).unmount

    assert result.unmounted?
    assert_equal [
      ["mount"],
      ["df", "-h"],
      ["diskutil", "eject", "/Volumes/CodexRAMFix"]
    ], runner.commands
  end

  def test_unmount_succeeds_without_eject_when_already_unmounted
    config = CodexSsdFix::Ramdisk.build
    runner = ScriptedRunner.new(
      ["mount"] => "/dev/disk1s1 on / (apfs, local)\n",
      ["df", "-h"] => "Filesystem Size Used Avail Capacity Mounted on\n/dev/disk1s1 100Gi 50Gi 50Gi 50% /\n"
    )

    result = CodexSsdFix::Ramdisk.new(config: config, runner: runner).unmount

    refute result.unmounted?
    assert_equal [["mount"], ["df", "-h"]], runner.commands
  end

  class RecordingRunner
    attr_reader :commands

    Result = Struct.new(:stdout)

    def initialize(stdout:)
      @stdout = stdout
      @commands = []
    end

    def run!(argv)
      @commands << argv
      Result.new(@stdout)
    end
  end

  class ScriptedRunner
    attr_reader :commands

    Result = Struct.new(:stdout)

    def initialize(responses)
      @responses = responses
      @commands = []
    end

    def run!(argv)
      @commands << argv
      Result.new(@responses.fetch(argv))
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

  class RecordingFileUtils
    attr_reader :mkdir_p_calls

    def initialize
      @mkdir_p_calls = []
    end

    def mkdir_p(paths)
      @mkdir_p_calls << paths
    end
  end
end
