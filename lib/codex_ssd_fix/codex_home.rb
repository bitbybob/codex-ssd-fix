# frozen_string_literal: true

module CodexSsdFix
  class CodexHome
    DB_FILENAME = "logs_2.sqlite"
    WAL_FILENAME = "#{DB_FILENAME}-wal"
    SHM_FILENAME = "#{DB_FILENAME}-shm"

    attr_reader :path

    def self.resolve(argv: [], env: ENV)
      new(home_from_argv(argv) || env["CODEX_HOME"] || "~/.codex")
    end

    def self.home_from_argv(argv)
      argv.each_with_index do |arg, index|
        return arg.delete_prefix("--home=") if arg.start_with?("--home=")
        if arg == "--home"
          raise ArgumentError, "codex home must not be blank" if argv[index + 1].nil?

          return argv[index + 1]
        end
      end

      nil
    end
    private_class_method :home_from_argv

    def initialize(home)
      @path = expand_home(validate_home(home))
    end

    def database_path
      File.join(path, DB_FILENAME)
    end

    def wal_path
      File.join(path, WAL_FILENAME)
    end

    def shm_path
      File.join(path, SHM_FILENAME)
    end

    def sidecar_paths
      [wal_path, shm_path]
    end

    private

    def validate_home(home)
      unless home.is_a?(String) && !home.strip.empty?
        raise ArgumentError, "codex home must not be blank"
      end

      home
    end

    def expand_home(home)
      File.expand_path(home)
    rescue ArgumentError => e
      raise ArgumentError, "invalid codex home: #{e.message}"
    end
  end
end
