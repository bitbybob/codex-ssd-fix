# frozen_string_literal: true

require "codex_ssd_fix/codex_home"
require "codex_ssd_fix/backup"
require "codex_ssd_fix/command_runner"

module CodexSsdFix
  class LogGuard
    ALL_TRIGGER = "codex_ssd_fix_block_log_inserts"
    TRACE_TRIGGER = "codex_ssd_fix_block_trace_logs"
    MODES = %w[all trace].freeze
    ApplyResult = Struct.new(:mode, :backup_path, keyword_init: true)

    def initialize(codex_home:, runner: CommandRunner.new, backup: Backup.new(codex_home: codex_home))
      @codex_home = codex_home
      @runner = runner
      @backup = backup
    end

    def apply(mode)
      mode = normalize_mode(mode)
      backup_result = @backup.create
      @runner.run!(["sqlite3", @codex_home.database_path, apply_sql(mode)])
      ApplyResult.new(mode: mode, backup_path: backup_result.path)
    end

    def apply_sql(mode)
      mode = normalize_mode(mode)
      trigger_sql = mode == "all" ? all_trigger_sql : trace_trigger_sql

      <<~SQL
        BEGIN;
        #{schema_sql}
        DROP TRIGGER IF EXISTS #{ALL_TRIGGER};
        DROP TRIGGER IF EXISTS #{TRACE_TRIGGER};
        #{trigger_sql}
        COMMIT;
      SQL
    end

    private

    def normalize_mode(mode)
      mode = mode.to_s
      return mode if MODES.include?(mode)

      raise ArgumentError, "mode must be one of: #{MODES.join(", ")}"
    end

    def schema_sql
      <<~SQL
        CREATE TABLE IF NOT EXISTS logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ts INTEGER NOT NULL,
            ts_nanos INTEGER NOT NULL,
            level TEXT NOT NULL,
            target TEXT NOT NULL,
            feedback_log_body TEXT,
            module_path TEXT,
            file TEXT,
            line INTEGER,
            thread_id TEXT,
            process_uuid TEXT,
            estimated_bytes INTEGER NOT NULL DEFAULT 0
        );
        CREATE INDEX IF NOT EXISTS idx_logs_ts ON logs(ts DESC, ts_nanos DESC, id DESC);
        CREATE INDEX IF NOT EXISTS idx_logs_thread_id ON logs(thread_id);
        CREATE INDEX IF NOT EXISTS idx_logs_thread_id_ts ON logs(thread_id, ts DESC, ts_nanos DESC, id DESC);
        CREATE INDEX IF NOT EXISTS idx_logs_process_uuid_threadless_ts
        ON logs(process_uuid, ts DESC, ts_nanos DESC, id DESC)
        WHERE thread_id IS NULL;
      SQL
    end

    def all_trigger_sql
      <<~SQL
        CREATE TRIGGER #{ALL_TRIGGER}
        BEFORE INSERT ON logs
        BEGIN
          SELECT RAISE(IGNORE);
        END;
      SQL
    end

    def trace_trigger_sql
      <<~SQL
        CREATE TRIGGER #{TRACE_TRIGGER}
        BEFORE INSERT ON logs
        WHEN NEW.level = 'TRACE'
        BEGIN
          SELECT RAISE(IGNORE);
        END;
      SQL
    end
  end
end
