# frozen_string_literal: true

module CodexSsdFix
  class Ramdisk
    DEFAULT_SIZE_GIB = 2
    DEFAULT_NAME = "CodexRAMFix"
    DEFAULT_MOUNT_POINT = "/Volumes/CodexRAMFix"
    BYTES_PER_GIB = 1024 * 1024 * 1024
    SECTOR_BYTES = 512
    SECTORS_PER_GIB = BYTES_PER_GIB / SECTOR_BYTES

    Config = Struct.new(:size_gib, :sectors, :name, :mount_point, keyword_init: true) do
      def ram_url
        "ram://#{sectors}"
      end

      def attach_command
        ["hdiutil", "attach", "-nomount", ram_url]
      end
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
  end
end
