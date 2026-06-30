# frozen_string_literal: true

require "fileutils"
require "codex_ssd_fix/command_runner"

module CodexSsdFix
  class Ramdisk
    class Error < StandardError; end

    DEFAULT_SIZE_GIB = 2
    DEFAULT_NAME = "CodexRAMFix"
    DEFAULT_MOUNT_POINT = "/Volumes/CodexRAMFix"
    SCRATCH_DIRNAME = "codex-scratch"
    SCRATCH_SUBDIRS = %w[attempts prompt-fu-runs tmp generic].freeze
    BYTES_PER_GIB = 1024 * 1024 * 1024
    SECTOR_BYTES = 512
    SECTORS_PER_GIB = BYTES_PER_GIB / SECTOR_BYTES

    MountResult = Struct.new(:config, :mounted, :device, :scratch_paths, keyword_init: true) do
      def mounted?
        mounted
      end
    end

    Config = Struct.new(:size_gib, :sectors, :name, :mount_point, keyword_init: true) do
      def ram_url
        "ram://#{sectors}"
      end

      def attach_command
        ["hdiutil", "attach", "-nomount", ram_url]
      end

      def erase_command(device)
        ["diskutil", "erasevolume", "HFS+", name, device]
      end

      def scratch_root
        File.join(mount_point, SCRATCH_DIRNAME)
      end

      def scratch_paths
        SCRATCH_SUBDIRS.map { |subdir| File.join(scratch_root, subdir) }
      end
    end

    def initialize(config: self.class.build, runner: CommandRunner.new, filesystem: File, fileutils: FileUtils)
      @config = config
      @runner = runner
      @filesystem = filesystem
      @fileutils = fileutils
    end

    def mount
      if mounted?
        create_scratch_layout
        return mount_result(mounted: false)
      end

      attach_result = @runner.run!(@config.attach_command)
      device = self.class.parse_device(attach_result.stdout)
      @runner.run!(@config.erase_command(device))
      create_scratch_layout
      mount_result(mounted: true, device: device)
    rescue CommandRunner::Error => e
      raise Error, e.message
    end

    def self.build(size_gib: nil, name: nil, mount_point: nil)
      size = parse_size_gib(size_gib)

      Config.new(
        size_gib: size,
        sectors: size * SECTORS_PER_GIB,
        name: parse_nonblank(name, "name") || DEFAULT_NAME,
        mount_point: parse_nonblank(mount_point, "mount point") || DEFAULT_MOUNT_POINT
      )
    end

    def self.parse_size_gib(value)
      return DEFAULT_SIZE_GIB if value.nil?
      return value if value.is_a?(Integer) && value.positive?

      text = value.to_s
      return text.to_i if text.match?(/\A[1-9]\d*\z/)

      raise ArgumentError, "size-gib must be a positive integer"
    end
    private_class_method :parse_size_gib

    def self.parse_nonblank(value, label)
      return nil if value.nil?

      text = value.to_s
      raise ArgumentError, "#{label} must not be blank" if text.strip.empty?

      text
    end
    private_class_method :parse_nonblank

    def self.parse_device(output)
      output.to_s.each_line do |line|
        token = line.split.find { |part| part.match?(/\A\/dev\/disk\d+(?:s\d+)?\z/) }
        return token if token
      end

      raise Error, "could not parse RAM disk device from hdiutil output"
    end

    def mounted?
      @filesystem.directory?(@config.mount_point)
    end

    def create_scratch_layout
      @fileutils.mkdir_p(@config.scratch_paths)
    end

    def mount_result(mounted:, device: nil)
      MountResult.new(
        config: @config,
        mounted: mounted,
        device: device,
        scratch_paths: @config.scratch_paths
      )
    end
  end
end
