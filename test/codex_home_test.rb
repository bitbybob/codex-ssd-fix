# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "codex_ssd_fix/codex_home"

class CodexHomeTest < Minitest::Test
  def test_default_home_resolves_to_current_user_codex_home
    model = CodexSsdFix::CodexHome.resolve(argv: [], env: {})

    assert_equal File.expand_path("~/.codex"), model.path
  end

  def test_environment_override_resolution
    path = File.join(Dir.tmpdir, "codex env home")

    model = CodexSsdFix::CodexHome.resolve(argv: [], env: { "CODEX_HOME" => path })

    assert_equal File.expand_path(path), model.path
  end

  def test_command_line_override_beats_environment
    cli_path = File.join(Dir.tmpdir, "codex cli home")
    env_path = File.join(Dir.tmpdir, "codex env home")

    model = CodexSsdFix::CodexHome.resolve(
      argv: ["--home", cli_path],
      env: { "CODEX_HOME" => env_path }
    )

    assert_equal File.expand_path(cli_path), model.path
  end

  def test_command_line_equals_form_beats_environment
    cli_path = File.join(Dir.tmpdir, "codex cli home")
    env_path = File.join(Dir.tmpdir, "codex env home")

    model = CodexSsdFix::CodexHome.resolve(
      argv: ["--home=#{cli_path}"],
      env: { "CODEX_HOME" => env_path }
    )

    assert_equal File.expand_path(cli_path), model.path
  end

  def test_paths_with_spaces_are_preserved
    path = File.join(Dir.tmpdir, "codex home with spaces")

    model = CodexSsdFix::CodexHome.new(path)

    assert_equal File.expand_path(path), model.path
    assert_includes model.database_path, "codex home with spaces"
  end

  def test_tilde_expansion
    model = CodexSsdFix::CodexHome.new("~/.codex")

    assert_equal File.expand_path("~/.codex"), model.path
  end

  def test_blank_homes_are_rejected
    ["", "   ", nil].each do |home|
      error = assert_raises(ArgumentError) { CodexSsdFix::CodexHome.new(home) }
      assert_equal "codex home must not be blank", error.message
    end
  end

  def test_missing_home_argument_is_rejected
    error = assert_raises(ArgumentError) do
      CodexSsdFix::CodexHome.resolve(argv: ["--home"], env: { "CODEX_HOME" => "/tmp/codex" })
    end

    assert_equal "codex home must not be blank", error.message
  end

  def test_log_database_paths_are_explicit
    model = CodexSsdFix::CodexHome.new("/tmp/codex")

    assert_equal "/tmp/codex/logs_2.sqlite", model.database_path
    assert_equal "/tmp/codex/logs_2.sqlite-wal", model.wal_path
    assert_equal "/tmp/codex/logs_2.sqlite-shm", model.shm_path
    assert_equal ["/tmp/codex/logs_2.sqlite-wal", "/tmp/codex/logs_2.sqlite-shm"], model.sidecar_paths
  end
end
