require "minitest/autorun"
require "base64"

module Spaceship
  module ConnectAPI
    class << self
      attr_accessor :requests, :failure

      def get_bundle_ids(limit:)
        self.requests += 1
        raise failure if failure
        []
      end
    end
  end
end

class ValidationLane
  attr_reader :matches

  def initialize
    @lanes = {}
    @matches = []
    instance_eval(File.read(File.expand_path("../Fastfile", __dir__)), "Fastfile")
  end

  def default_platform(*)
  end

  def platform(*)
    yield
  end

  def desc(*)
  end

  def lane(name, &block)
    @lanes[name] = block
  end
  alias private_lane lane

  def app_store_connect_api_key(**options)
  end

  def match(**options)
    @matches << options
    raise "No code signing identity found" if ENV["MATCH_REPOSITORY_EMPTY"] == "true"
  end

  def run
    instance_exec(&@lanes.fetch(:validate_secrets))
  end

  def method_missing(name, *args)
    return instance_exec(*args, &@lanes[name]) if @lanes.key?(name)
    super
  end
end

module UI
  def self.important(message)
  end
end

class ValidateSecretsTest < Minitest::Test
  def setup
    @original_env = ENV.to_h
    ENV.delete("CI")
    ENV.delete("MATCH_REPOSITORY_EMPTY")
    Spaceship::ConnectAPI.requests = 0
    Spaceship::ConnectAPI.failure = nil
    @lane = ValidationLane.new
  end

  def teardown
    ENV.replace(@original_env)
  end

  def test_empty_repository_allows_first_certificate_creation_after_checking_apple_access
    ENV["MATCH_REPOSITORY_EMPTY"] = "true"
    @lane.run
    assert_equal 1, Spaceship::ConnectAPI.requests
    assert_empty @lane.matches
  end

  def test_existing_repository_still_checks_decryption_in_readonly_mode
    ENV["MATCH_REPOSITORY_EMPTY"] = "false"
    @lane.run
    assert_equal 1, Spaceship::ConnectAPI.requests
    assert_equal 1, @lane.matches.length
    assert_equal true, @lane.matches.first.fetch(:readonly)
  end

  def test_missing_empty_repository_flag_does_not_skip_match
    @lane.run
    assert_equal 1, @lane.matches.length
  end

  def test_empty_repository_does_not_hide_invalid_apple_credentials
    ENV["MATCH_REPOSITORY_EMPTY"] = "true"
    Spaceship::ConnectAPI.failure = RuntimeError.new("Apple rejected API credentials")
    error = assert_raises(RuntimeError) { @lane.run }
    assert_equal "Apple rejected API credentials", error.message
    assert_empty @lane.matches
  end
end
