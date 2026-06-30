# frozen_string_literal: true

require "codex_ssd_fix/ramdisk"
require "shellwords"

module CodexSsdFix
  class EnvGuide
    Result = Struct.new(:ok, :output, keyword_init: true) do
      def exit_status
        ok ? 0 : 1
      end
    end

    def initialize(ramdisk: Ramdisk.new)
      @ramdisk = ramdisk
    end

    def run
      status = @ramdisk.status
      return not_mounted(status.config) unless status.mounted?

      Result.new(ok: true, output: mounted_output(status.config))
    end

    private

    def not_mounted(config)
      Result.new(
        ok: false,
        output: <<~OUTPUT
          #{mount_command(config)}
          # RAM disk is not mounted. Run the command above first.
        OUTPUT
      )
    end

    def mount_command(config)
      args = %w[codex-ssd-fix ramdisk mount]
      args.concat(["--size-gib", config.size_gib.to_s]) if config.size_gib != Ramdisk::DEFAULT_SIZE_GIB
      args.concat(["--name", config.name]) if config.name != Ramdisk::DEFAULT_NAME
      args.concat(["--mount-point", config.mount_point]) if config.mount_point != Ramdisk::DEFAULT_MOUNT_POINT
      args.shelljoin
    end

    def mounted_output(config)
      <<~OUTPUT
        # codex-ssd-fix scratch environment
        # Keep CODEX_HOME on durable storage; do not point it at #{config.mount_point}.
        export TMPDIR=#{File.join(config.scratch_root, "tmp")}

        # Generic attempt scratch root:
        export CODEX_ATTEMPT_ROOT=#{File.join(config.scratch_root, "attempts")}

        # Generic run scratch root:
        export CODEX_RUN_ROOT=#{File.join(config.scratch_root, "generic")}
      OUTPUT
    end
  end
end
