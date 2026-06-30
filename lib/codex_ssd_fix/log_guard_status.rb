# frozen_string_literal: true

require "codex_ssd_fix/codex_home"
require "codex_ssd_fix/command_runner"
require "codex_ssd_fix/log_guard"

module CodexSsdFix
  class LogGuardStatus
    class Error < StandardError; end

    Result = Struct.new(:output, keyword_init: true) do
      def exit_status
        0
      end
    end

    def initialize(codex_home:, runner: CommandRunner.new, filesystem: File)
      @codex_home = codex_home
      @runner = runner
      @filesystem = filesystem
    end

    def report
      raise Error, "database missing: #{@codex_home.database_path}" unless @filesystem.exist?(@codex_home.database_path)

      triggers = trigger_names
      stats = database_stats

      Result.new(output: "#{report_lines(triggers, stats).join("\n")}\n")
    end

    private

    def trigger_names
      sqlite_read(<<~SQL).lines.map(&:strip).reject(&:empty?)
        SELECT name
        FROM sqlite_schema
        WHERE type = 'trigger' AND name LIKE 'codex_ssd_fix_%'
        ORDER BY name;
      SQL
    end

    def database_stats
      raw = sqlite_read(<<~SQL).strip
        SELECT COUNT(*), COALESCE(MAX(id), ''), COALESCE(MAX(ts), '')
        FROM logs;
      SQL

      count, max_id, max_ts = raw.split("|", 3)
      {
        row_count: count || "0",
        max_id: blank_to_none(max_id),
        max_timestamp: blank_to_none(max_ts)
      }
    end

    def sqlite_read(sql)
      @runner.run!(["sqlite3", "-readonly", @codex_home.database_path, sql]).stdout
    rescue CommandRunner::Error => e
      raise Error, e.message
    end

    def report_lines(triggers, stats)
      [
        "codex-ssd-fix guard status",
        "codex home: #{@codex_home.path}",
        "database: #{@codex_home.database_path}",
        "guard: #{guard_state(triggers)}",
        "triggers: #{triggers.empty? ? "(none)" : triggers.join(", ")}",
        "row count: #{stats.fetch(:row_count)}",
        "max id: #{stats.fetch(:max_id)}",
        "max timestamp: #{stats.fetch(:max_timestamp)}",
        "logs_2.sqlite bytes: #{byte_size(@codex_home.database_path)}",
        "logs_2.sqlite-wal bytes: #{byte_size(@codex_home.wal_path)}",
        "logs_2.sqlite-shm bytes: #{byte_size(@codex_home.shm_path)}"
      ]
    end

    def guard_state(triggers)
      if triggers.include?(LogGuard::ALL_TRIGGER)
        "all"
      elsif triggers.include?(LogGuard::TRACE_TRIGGER)
        "trace"
      else
        "none"
      end
    end

    def byte_size(path)
      return @filesystem.size(path) if @filesystem.exist?(path)

      0
    end

    def blank_to_none(value)
      value.nil? || value.empty? ? "(none)" : value
    end
  end
end
