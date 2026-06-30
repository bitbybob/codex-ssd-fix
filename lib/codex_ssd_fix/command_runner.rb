# frozen_string_literal: true

require "open3"

module CodexSsdFix
  class CommandRunner
    Result = Struct.new(:argv, :stdout, :stderr, :exit_status, :elapsed_seconds, keyword_init: true) do
      def success?
        exit_status.zero?
      end

      def executable
        argv.first
      end

      def error_message
        return nil if success?

        message = +"#{executable} failed with exit status #{exit_status}"
        clean_stderr = stderr.to_s.strip
        message << ": #{clean_stderr}" unless clean_stderr.empty?
        message
      end
    end

    class Error < StandardError
      attr_reader :result

      def initialize(result)
        @result = result
        super(result.error_message)
      end
    end

    def initialize(capture3: nil, clock: Process)
      @capture3 = capture3 || method(:capture3)
      @clock = clock
    end

    def run(argv)
      validate_argv!(argv)

      started_at = monotonic_time
      stdout, stderr, status = @capture3.call(argv)
      elapsed_seconds = monotonic_time - started_at

      Result.new(
        argv: argv.dup.freeze,
        stdout: stdout,
        stderr: stderr,
        exit_status: status.exitstatus,
        elapsed_seconds: elapsed_seconds
      )
    end

    def run!(argv)
      result = run(argv)
      raise Error, result unless result.success?

      result
    end

    private

    def capture3(argv)
      Open3.capture3(*argv)
    end

    def monotonic_time
      @clock.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def validate_argv!(argv)
      unless argv.is_a?(Array) && argv.any? && argv.all? { |arg| arg.is_a?(String) && !arg.empty? }
        raise ArgumentError, "argv must be a non-empty array of strings"
      end
    end
  end
end
