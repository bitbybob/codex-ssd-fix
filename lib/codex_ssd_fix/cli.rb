# frozen_string_literal: true

module CodexSsdFix
  class CLI
    COMMANDS = {
      "guard" => "apply|status|remove",
      "ramdisk" => "mount|status|unmount",
      "env" => nil,
      "doctor" => nil
    }.freeze

    def initialize(stdout: $stdout, stderr: $stderr)
      @stdout = stdout
      @stderr = stderr
    end

    def run(argv)
      command = argv.first || "help"

      case command
      when "help", "-h", "--help"
        print_help
        0
      when "doctor"
        require "codex_ssd_fix/doctor"
        result = Doctor.new.run
        @stdout.write result.output
        result.exit_status
      when "guard"
        handle_guard(argv.drop(1))
      when "ramdisk"
        handle_ramdisk(argv.drop(1))
      when *COMMANDS.keys
        @stdout.puts "#{command}: not implemented yet"
        0
      else
        @stderr.puts "unknown command: #{command}"
        @stderr.puts "run `codex-ssd-fix help` for usage"
        1
      end
    end

    private

    def handle_guard(argv)
      action = argv.first
      unless %w[apply status remove].include?(action)
        @stdout.puts "guard: not implemented yet"
        return 0
      end

      require "codex_ssd_fix/codex_home"
      require "codex_ssd_fix/backup"
      require "codex_ssd_fix/command_runner"
      require "codex_ssd_fix/log_guard_status"
      codex_home = CodexHome.resolve(argv: argv)

      if action == "status"
        result = LogGuardStatus.new(codex_home: codex_home).report
        @stdout.write result.output
        return result.exit_status
      end

      require "codex_ssd_fix/log_guard"
      if action == "remove"
        result = LogGuard.new(codex_home: codex_home).remove
        @stdout.puts "backup: #{result.backup_path}"
        @stdout.puts "guard remove: removed tool-owned triggers"
        return 0
      end

      mode = option_value(argv, "--mode")
      result = LogGuard.new(codex_home: codex_home).apply(mode)
      @stdout.puts "backup: #{result.backup_path}"
      @stdout.puts "guard apply: installed #{result.mode} mode"
      0
    rescue ArgumentError, Backup::Error, CommandRunner::Error, LogGuardStatus::Error => e
      @stderr.puts e.message
      1
    end

    def option_value(argv, option)
      argv.each_with_index do |arg, index|
        return arg.delete_prefix("#{option}=") if arg.start_with?("#{option}=")
        return argv[index + 1] if arg == option
      end

      nil
    end

    def handle_ramdisk(argv)
      action = argv.first
      unless %w[mount status unmount].include?(action)
        @stdout.puts "ramdisk: not implemented yet"
        return 0
      end

      if action == "mount"
        require "codex_ssd_fix/ramdisk"
        Ramdisk.build(
          size_gib: optional_value(argv, "--size-gib"),
          name: optional_value(argv, "--name"),
          mount_point: optional_value(argv, "--mount-point")
        )
      end

      @stdout.puts "ramdisk #{action}: not implemented yet"
      0
    rescue ArgumentError => e
      @stderr.puts e.message
      1
    end

    def optional_value(argv, option)
      return nil unless option_supplied?(argv, option)

      option_value(argv, option) || ""
    end

    def option_supplied?(argv, option)
      argv.any? { |arg| arg == option || arg.start_with?("#{option}=") }
    end

    def print_help
      @stdout.puts <<~USAGE
        usage: codex-ssd-fix <command> [args]

        commands:
          guard apply|status|remove
          ramdisk mount|status|unmount
          env
          doctor
          help
      USAGE
    end
  end
end
