# frozen_string_literal: true

require "fileutils"
require "minitest/autorun"
require "tmpdir"
require "codex_ssd_fix/codex_home"
require "codex_ssd_fix/command_runner"
require "codex_ssd_fix/log_guard"

class LogGuardTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir("codex-ssd-fix")
    @home = CodexSsdFix::CodexHome.new(@tmpdir)
    @guard = CodexSsdFix::LogGuard.new(codex_home: @home, runner: CodexSsdFix::CommandRunner.new)
  end

  def teardown
    FileUtils.remove_entry(@tmpdir) if @tmpdir
  end

  def test_all_mode_blocks_info_insert_and_is_idempotent
    @guard.apply("all")
    @guard.apply("all")

    insert_log("INFO")

    assert_equal 0, log_count
    assert_equal [CodexSsdFix::LogGuard::ALL_TRIGGER], tool_triggers
  end

  def test_trace_mode_blocks_trace_and_allows_info_and_is_idempotent
    @guard.apply("trace")
    @guard.apply("trace")

    insert_log("TRACE")
    insert_log("INFO")

    assert_equal 1, log_count
    assert_equal ["INFO"], log_levels
    assert_equal [CodexSsdFix::LogGuard::TRACE_TRIGGER], tool_triggers
  end

  def test_switching_from_all_to_trace_replaces_tool_owned_trigger
    @guard.apply("all")
    @guard.apply("trace")

    insert_log("INFO")

    assert_equal 1, log_count
    assert_equal [CodexSsdFix::LogGuard::TRACE_TRIGGER], tool_triggers
  end

  def test_switching_from_trace_to_all_replaces_tool_owned_trigger
    @guard.apply("trace")
    @guard.apply("all")

    insert_log("INFO")

    assert_equal 0, log_count
    assert_equal [CodexSsdFix::LogGuard::ALL_TRIGGER], tool_triggers
  end

  def test_generated_sql_does_not_contain_vacuum
    refute_includes @guard.apply_sql("all").upcase, "VACUUM"
    refute_includes @guard.apply_sql("trace").upcase, "VACUUM"
  end

  def test_invalid_mode_is_rejected
    error = assert_raises(ArgumentError) { @guard.apply_sql("debug") }

    assert_equal "mode must be one of: all, trace", error.message
  end

  def test_mutation_is_not_invoked_when_backup_fails
    runner = RecordingRunner.new
    backup = FailingBackup.new
    guard = CodexSsdFix::LogGuard.new(codex_home: @home, runner: runner, backup: backup)

    error = assert_raises(RuntimeError) { guard.apply("all") }

    assert_equal "backup failed", error.message
    assert_empty runner.commands
  end

  def test_remove_drops_all_mode_trigger
    @guard.apply("all")

    result = @guard.remove

    assert File.directory?(result.backup_path)
    assert_empty tool_triggers
  end

  def test_remove_drops_trace_mode_trigger
    @guard.apply("trace")

    @guard.remove

    assert_empty tool_triggers
  end

  def test_remove_preserves_unrelated_trigger_and_rows
    @guard.apply("trace")
    create_unrelated_trigger
    insert_log("INFO")

    @guard.remove

    assert_empty tool_triggers
    assert_equal ["user_keep_logs"], all_triggers
    assert_equal 1, log_count
  end

  def test_remove_creates_backup_before_mutation
    @guard.apply("all")
    runner = RecordingRunner.new
    backup = RecordingBackup.new("/tmp/backup")
    guard = CodexSsdFix::LogGuard.new(codex_home: @home, runner: runner, backup: backup)

    result = guard.remove

    assert_equal "/tmp/backup", result.backup_path
    assert backup.created
    assert_equal 1, runner.commands.length
    assert_includes runner.commands.first.last, "DROP TRIGGER IF EXISTS #{CodexSsdFix::LogGuard::ALL_TRIGGER}"
  end

  def test_remove_does_not_mutate_when_backup_fails
    runner = RecordingRunner.new
    backup = FailingBackup.new
    guard = CodexSsdFix::LogGuard.new(codex_home: @home, runner: runner, backup: backup)

    error = assert_raises(RuntimeError) { guard.remove }

    assert_equal "backup failed", error.message
    assert_empty runner.commands
  end

  def test_remove_sql_checkpoints_wal_and_does_not_vacuum
    sql = @guard.remove_sql

    assert_includes sql, "PRAGMA wal_checkpoint(TRUNCATE);"
    refute_includes sql.upcase, "VACUUM"
  end

  private

  class RecordingRunner
    attr_reader :commands

    def initialize
      @commands = []
    end

    def run!(argv)
      @commands << argv
    end
  end

  class FailingBackup
    def create
      raise "backup failed"
    end
  end

  class RecordingBackup
    Result = Struct.new(:path)
    attr_reader :created

    def initialize(path)
      @path = path
      @created = false
    end

    def create
      @created = true
      Result.new(@path)
    end
  end

  def insert_log(level)
    sqlite3(<<~SQL)
      INSERT INTO logs (ts, ts_nanos, level, target, estimated_bytes)
      VALUES (1, 0, '#{level}', 'test', 0);
    SQL
  end

  def log_count
    sqlite3("SELECT COUNT(*) FROM logs;").to_i
  end

  def log_levels
    sqlite3("SELECT level FROM logs ORDER BY id;").lines.map(&:strip)
  end

  def tool_triggers
    sqlite3(<<~SQL).lines.map(&:strip)
      SELECT name
      FROM sqlite_schema
      WHERE type = 'trigger' AND name LIKE 'codex_ssd_fix_%'
      ORDER BY name;
    SQL
  end

  def all_triggers
    sqlite3(<<~SQL).lines.map(&:strip)
      SELECT name
      FROM sqlite_schema
      WHERE type = 'trigger'
      ORDER BY name;
    SQL
  end

  def create_unrelated_trigger
    sqlite3(<<~SQL)
      CREATE TRIGGER user_keep_logs
      BEFORE INSERT ON logs
      WHEN NEW.level = 'DEBUG'
      BEGIN
        SELECT RAISE(IGNORE);
      END;
    SQL
  end

  def sqlite3(sql)
    result = CodexSsdFix::CommandRunner.new.run!(["sqlite3", @home.database_path, sql])
    result.stdout
  end
end
