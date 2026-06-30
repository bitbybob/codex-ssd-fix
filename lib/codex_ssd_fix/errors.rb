# frozen_string_literal: true

module CodexSsdFix
  module Errors
    SUCCESS = 0
    RUNTIME_FAILURE = 1
    USAGE_ERROR = 2

    class UsageError < StandardError; end
  end
end
