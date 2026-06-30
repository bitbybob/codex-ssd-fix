# frozen_string_literal: true

require "codex_ssd_fix/command_runner"

module CodexSsdFix
  class Doctor
    REQUIRED_EXECUTABLES = %w[sqlite3 hdiutil diskutil].freeze

    Result = Struct.new(:ok, :output, keyword_init: true) do
      def exit_status
        ok ? 0 : 1
      end
    end

    def initialize(
      runner: CommandRunner.new,
      platform: RUBY_PLATFORM,
      codex_home: File.expand_path("~/.codex"),
      filesystem: File
    )
      @runner = runner
      @platform = platform
      @codex_home = codex_home
      @filesystem = filesystem
    end

    def run
      lines = ["codex-ssd-fix doctor"]
      ok = true

      if macos?
        lines << "macos: supported (#{@platform})"
      else
        ok = false
        lines << "macos: unsupported (#{@platform})"
        lines << "  remediation: run this tool on macOS."
      end

      REQUIRED_EXECUTABLES.each do |executable|
        if executable_found?(executable)
          lines << "#{executable}: found"
        else
          ok = false
          lines << "#{executable}: missing"
          lines << "  remediation: install #{executable} or ensure it is available on PATH."
        end
      end

      codex_home_ok, codex_home_output = codex_home_check
      ok &&= codex_home_ok
      lines.concat(codex_home_output)

      Result.new(ok: ok, output: "#{lines.join("\n")}\n")
    end

    private

    def macos?
      @platform.include?("darwin")
    end

    def executable_found?(executable)
      @runner.run(["/usr/bin/which", executable]).success?
    rescue Errno::ENOENT
      @runner.run(["which", executable]).success?
    end

    def codex_home_check
      unless @filesystem.exist?(@codex_home)
        return [
          true,
          [
            "codex home: not found (#{@codex_home})",
            "  note: write access not checked because the directory does not exist."
          ]
        ]
      end

      if @filesystem.directory?(@codex_home) && @filesystem.writable?(@codex_home)
        [true, ["codex home: writable (#{@codex_home})"]]
      elsif @filesystem.directory?(@codex_home)
        [
          false,
          [
            "codex home: not writable (#{@codex_home})",
            "  remediation: fix directory permissions before applying guard changes."
          ]
        ]
      else
        [
          false,
          [
            "codex home: not a directory (#{@codex_home})",
            "  remediation: move or remove this path before applying guard changes."
          ]
        ]
      end
    end
  end
end
