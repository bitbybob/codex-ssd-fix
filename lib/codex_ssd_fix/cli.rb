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
