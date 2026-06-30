# frozen_string_literal: true

require "test_helper"
require "codex_ssd_fix/codex_home"
require "codex_ssd_fix/command_runner"
require "codex_ssd_fix/log_guard"
require "codex_ssd_fix/log_guard_status"

class LogGuardStatusTest < Minitest::Test
  def setup
    @tmpdir = make_tempdir
    @home = CodexSsdFix::CodexHome.new(@tmpdir)
    @runner = CodexSsdFix::CommandRunner.new
  end

  def test_status_on_guarded_database
    create_logs_database
    sqlite3("INSERT INTO logs (ts, ts_nanos, level, target, estimated_bytes) VALUES (10, 7, 'INFO', 'test', 0);")
    CodexSsdFix::LogGuard.new(codex_home: @home, runner: @runner).apply("trace")

    result = CodexSsdFix::LogGuardStatus.new(codex_home: @home, runner: @runner).report

    assert_equal 0, result.exit_status
    assert_includes result.output, "codex home: #{@home.path}"
    assert_includes result.output, "database: #{@home.database_path}"
    assert_includes result.output, "guard: trace"
    assert_includes result.output, "triggers: #{CodexSsdFix::LogGuard::TRACE_TRIGGER}"
    assert_includes result.output, "row count: 1"
    assert_includes result.output, "max id: 1"
    assert_includes result.output, "max timestamp: 10"
    assert_includes result.output, "logs_2.sqlite bytes: "
    assert_includes result.output, "logs_2.sqlite-wal bytes: "
    assert_includes result.output, "logs_2.sqlite-shm bytes: "
  end

  def test_status_on_unguarded_database
    create_logs_database

    result = CodexSsdFix::LogGuardStatus.new(codex_home: @home, runner: @runner).report

    assert_includes result.output, "guard: none"
    assert_includes result.output, "triggers: (none)"
    assert_includes result.output, "row count: 0"
    assert_includes result.output, "max id: (none)"
    assert_includes result.output, "max timestamp: (none)"
  end

  def test_missing_database_fails_without_creating_files
    error = assert_raises(CodexSsdFix::LogGuardStatus::Error) do
      CodexSsdFix::LogGuardStatus.new(codex_home: @home, runner: @runner).report
    end

    assert_equal "database missing: #{@home.database_path}", error.message
    refute File.exist?(@home.database_path)
    assert_empty Dir.children(@tmpdir)
  end

  def test_status_uses_readonly_sqlite
    create_logs_database
    runner = CodexSsdFix::RecordingCommandRunner.new(stdout: "0||\n")

    CodexSsdFix::LogGuardStatus.new(codex_home: @home, runner: runner).report

    assert runner.commands.all? { |argv| argv[0, 2] == ["sqlite3", "-readonly"] }
  end

  private

  def create_logs_database
    sqlite3(<<~SQL)
      CREATE TABLE logs (
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
    SQL
  end

  def sqlite3(sql)
    @runner.run!(["sqlite3", @home.database_path, sql]).stdout
  end
end
