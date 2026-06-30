# frozen_string_literal: true

require "codex_ssd_fix/errors"

module CodexSsdFix
  class CLI
    COMMANDS = {
      "guard" => "apply|status|remove",
      "ramdisk" => "mount|status|unmount",
      "env" => nil,
      "doctor" => nil
    }.freeze

    def initialize(stdout: $stdout, stderr: $stderr, runner: nil, filesystem: File, fileutils: nil)
      @stdout = stdout
      @stderr = stderr
      @runner = runner
      @filesystem = filesystem
      @fileutils = fileutils
    end

    def run(argv)
      command = argv.first || "help"

      case command
      when "help", "-h", "--help"
        print_help
        Errors::SUCCESS
      when "doctor"
        require "codex_ssd_fix/doctor"
        result = Doctor.new(runner: command_runner).run
        @stdout.write result.output
        result.exit_status
      when "env"
        handle_env(argv.drop(1))
      when "guard"
        handle_guard(argv.drop(1))
      when "ramdisk"
        handle_ramdisk(argv.drop(1))
      when *COMMANDS.keys
        usage_error("#{command}: missing action", "usage: codex-ssd-fix #{command} #{COMMANDS.fetch(command)}")
      else
        usage_error("unknown command: #{command}", "run `codex-ssd-fix help` for usage")
      end
    end

    private

    def handle_env(argv)
      require "codex_ssd_fix/ramdisk"
      require "codex_ssd_fix/env_guide"

      config = Ramdisk.build(
        size_gib: optional_value(argv, "--size-gib"),
        name: optional_value(argv, "--name"),
        mount_point: optional_value(argv, "--mount-point")
      )
      result = EnvGuide.new(
        ramdisk: Ramdisk.new(
          config: config,
          runner: command_runner,
          filesystem: @filesystem,
          fileutils: @fileutils || FileUtils
        )
      ).run
      @stdout.write result.output
      result.exit_status
    rescue ArgumentError, Errors::UsageError => e
      usage_error(e.message)
    rescue CommandRunner::Error, Ramdisk::Error => e
      runtime_failure(e.message)
    end

    def handle_guard(argv)
      action = argv.first
      unless %w[apply status remove].include?(action)
        return usage_error("invalid guard action: #{action || "(missing)"}", "usage: codex-ssd-fix guard apply|status|remove")
      end

      require "codex_ssd_fix/codex_home"
      require "codex_ssd_fix/backup"
      require "codex_ssd_fix/command_runner"
      require "codex_ssd_fix/log_guard_status"
      codex_home = CodexHome.resolve(argv: argv)

      if action == "status"
        result = LogGuardStatus.new(codex_home: codex_home, runner: command_runner).report
        @stdout.write result.output
        return result.exit_status
      end

      require "codex_ssd_fix/log_guard"
      if action == "remove"
        result = LogGuard.new(codex_home: codex_home, runner: command_runner).remove
        @stdout.puts "backup: #{result.backup_path}"
        @stdout.puts "guard remove: removed tool-owned triggers"
        return Errors::SUCCESS
      end

      mode = option_value(argv, "--mode")
      result = LogGuard.new(codex_home: codex_home, runner: command_runner).apply(mode)
      @stdout.puts "backup: #{result.backup_path}"
      @stdout.puts "guard apply: installed #{result.mode} mode"
      Errors::SUCCESS
    rescue ArgumentError, Errors::UsageError => e
      usage_error(e.message)
    rescue Backup::Error, CommandRunner::Error, LogGuardStatus::Error => e
      runtime_failure(e.message)
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
        return usage_error("invalid ramdisk action: #{action || "(missing)"}", "usage: codex-ssd-fix ramdisk mount|status|unmount")
      end

      require "codex_ssd_fix/ramdisk"
      config = Ramdisk.build(
        size_gib: optional_value(argv, "--size-gib"),
        name: optional_value(argv, "--name"),
        mount_point: optional_value(argv, "--mount-point")
      )
      ramdisk = Ramdisk.new(
        config: config,
        runner: command_runner,
        filesystem: @filesystem,
        fileutils: @fileutils || FileUtils
      )

      if action == "mount"
        result = ramdisk.mount
        @stdout.puts "ramdisk mount: #{result.mounted? ? "mounted" : "already mounted"}"
        @stdout.puts "mount point: #{result.config.mount_point}"
        @stdout.puts "device: #{result.device}" if result.device
        @stdout.puts "scratch root: #{result.config.scratch_root}"
        result.scratch_paths.each { |path| @stdout.puts "scratch path: #{path}" }
        return Errors::SUCCESS
      end

      if action == "status"
        result = ramdisk.status
        @stdout.puts "ramdisk status: #{result.mounted? ? "mounted" : "not mounted"}"
        @stdout.puts "mount point: #{result.config.mount_point}"
        result.scratch_paths.each { |path| @stdout.puts "scratch path: #{path}" }
        return Errors::SUCCESS
      end

      result = ramdisk.unmount
      @stdout.puts "ramdisk unmount: #{result.unmounted? ? "unmounted" : "already unmounted"}"
      @stdout.puts "mount point: #{result.config.mount_point}"
      Errors::SUCCESS
    rescue ArgumentError, Errors::UsageError => e
      usage_error(e.message)
    rescue CommandRunner::Error, Ramdisk::Error => e
      runtime_failure(e.message)
    end

    def optional_value(argv, option)
      return nil unless option_supplied?(argv, option)

      option_value(argv, option) || ""
    end

    def option_supplied?(argv, option)
      argv.any? { |arg| arg == option || arg.start_with?("#{option}=") }
    end

    def command_runner
      @runner ||= begin
        require "codex_ssd_fix/command_runner"
        CommandRunner.new
      end
    end

    def usage_error(*lines)
      lines.each { |line| @stderr.puts line }
      Errors::USAGE_ERROR
    end

    def runtime_failure(message)
      @stderr.puts message
      Errors::RUNTIME_FAILURE
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
