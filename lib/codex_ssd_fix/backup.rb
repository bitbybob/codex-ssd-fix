# frozen_string_literal: true

require "fileutils"

module CodexSsdFix
  class Backup
    class Error < StandardError; end

    Result = Struct.new(:path, :copied_paths, keyword_init: true)

    def initialize(codex_home:, clock: -> { Time.now.utc }, file_utils: FileUtils)
      @codex_home = codex_home
      @clock = clock
      @file_utils = file_utils
    end

    def create
      backup_dir = next_backup_dir
      @file_utils.mkdir_p(backup_dir)

      copied_paths = source_paths.each_with_object([]) do |source_path, copied|
        next unless File.exist?(source_path)

        destination_path = File.join(backup_dir, File.basename(source_path))
        @file_utils.cp(source_path, destination_path)
        copied << destination_path
      end

      Result.new(path: backup_dir, copied_paths: copied_paths)
    rescue SystemCallError, IOError => e
      raise Error, "backup failed: #{e.message}"
    end

    private

    def source_paths
      [@codex_home.database_path, @codex_home.wal_path, @codex_home.shm_path]
    end

    def next_backup_dir
      root = File.join(@codex_home.path, "log-db-backups")
      timestamp = @clock.call.utc.strftime("%Y%m%d%H%M%S%6N")
      candidate = File.join(root, timestamp)
      suffix = 0

      while File.exist?(candidate)
        suffix += 1
        candidate = File.join(root, "#{timestamp}-#{suffix.to_s.rjust(2, "0")}")
      end

      candidate
    end
  end
end
