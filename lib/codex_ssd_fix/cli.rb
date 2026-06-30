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
      unless action == "apply"
        @stdout.puts "guard: not implemented yet"
        return 0
      end

      require "codex_ssd_fix/codex_home"
      require "codex_ssd_fix/log_guard"

      mode = option_value(argv, "--mode")
      result = CodexHome.resolve(argv: argv).then do |codex_home|
        LogGuard.new(codex_home: codex_home).apply(mode)
      end
      @stdout.puts "backup: #{result.backup_path}"
      @stdout.puts "guard apply: installed #{result.mode} mode"
      0
    rescue ArgumentError, Backup::Error, CommandRunner::Error => e
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
