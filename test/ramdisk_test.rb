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
end
