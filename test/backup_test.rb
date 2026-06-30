# frozen_string_literal: true

require "test_helper"
require "codex_ssd_fix/backup"
require "codex_ssd_fix/codex_home"

class BackupTest < Minitest::Test
  def setup
    @tmpdir = make_tempdir
    @home = CodexSsdFix::CodexHome.new(@tmpdir)
    @clock = -> { Time.utc(2026, 6, 30, 17, 41, 5, 123456) }
  end

  def test_backup_copies_database_and_sidecars_when_present
    write_file(@home.database_path, "database")
    write_file(@home.wal_path, "wal")
    write_file(@home.shm_path, "shm")

    result = CodexSsdFix::Backup.new(codex_home: @home, clock: @clock).create

    assert_equal File.join(@home.path, "log-db-backups", "20260630174105123456"), result.path
    assert_equal "database", File.read(File.join(result.path, "logs_2.sqlite"))
    assert_equal "wal", File.read(File.join(result.path, "logs_2.sqlite-wal"))
    assert_equal "shm", File.read(File.join(result.path, "logs_2.sqlite-shm"))
    assert_equal 3, result.copied_paths.length
  end

  def test_backup_succeeds_when_only_database_exists
    write_file(@home.database_path, "database")

    result = CodexSsdFix::Backup.new(codex_home: @home, clock: @clock).create

    assert_equal ["logs_2.sqlite"], Dir.children(result.path)
    assert_equal "database", File.read(File.join(result.path, "logs_2.sqlite"))
  end

  def test_backup_directory_collision_gets_sortable_suffix
    existing = File.join(@home.path, "log-db-backups", "20260630174105123456")
    FileUtils.mkdir_p(existing)

    result = CodexSsdFix::Backup.new(codex_home: @home, clock: @clock).create

    assert_equal File.join(@home.path, "log-db-backups", "20260630174105123456-01"), result.path
  end

  def test_copy_failure_is_reported_as_backup_error
    write_file(@home.database_path, "database")

    error = assert_raises(CodexSsdFix::Backup::Error) do
      CodexSsdFix::Backup.new(codex_home: @home, clock: @clock, file_utils: FailingFileUtils.new).create
    end

    assert_includes error.message, "backup failed:"
    assert_includes error.message, "copy denied"
  end

  private

  class FailingFileUtils
    def mkdir_p(path)
      FileUtils.mkdir_p(path)
    end

    def cp(_source, _destination)
      raise Errno::EACCES, "copy denied"
    end
  end
end
