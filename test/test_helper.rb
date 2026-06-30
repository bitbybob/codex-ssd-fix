# frozen_string_literal: true

require "fileutils"
require "minitest/autorun"
require "tmpdir"

module CodexSsdFix
  module TestSupport
    CommandResult = Struct.new(:stdout)

    def make_tempdir(prefix = "codex-ssd-fix")
      dir = Dir.mktmpdir(prefix)
      tempdirs << dir
      dir
    end

    def teardown
      tempdirs.reverse_each do |dir|
        FileUtils.remove_entry(dir) if File.exist?(dir)
      end
      super
    end

    def write_file(path, body)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, body)
    end

    private

    def tempdirs
      @__codex_ssd_fix_tempdirs ||= []
    end
  end

  class RecordingCommandRunner
    attr_reader :commands

    def initialize(stdout: "", responses: nil)
      @stdout = stdout
      @responses = responses
      @commands = []
    end

    def run!(argv)
      @commands << argv
      TestSupport::CommandResult.new(response_for(argv))
    end

    private

    def response_for(argv)
      return @responses.fetch(argv) if @responses

      @stdout
    end
  end
end

class Minitest::Test
  include CodexSsdFix::TestSupport
end
