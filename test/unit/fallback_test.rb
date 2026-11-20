require_relative "helper"

describe Fallback do
  let(:remote) { Minitest::Mock.new }
  let(:local) { Minitest::Mock.new }

  it "returns the daemon's reply" do
    remote.expect(:token, "ok me tok", ["github.com", ""])
    assert_equal "ok me tok", Fallback.new(remote, local, false).token("github.com", "")
    remote.verify
  end

  it "decides in this process when there is no daemon" do
    remote.expect(:token, "down", ["github.com", ""])
    local.expect(:token, "ok me tok", ["github.com", ""])
    assert_equal "ok me tok", Fallback.new(remote, local, false).token("github.com", "")
    local.verify
  end

  it "gives no token when a daemon is required and there is none" do
    remote.expect(:token, "down", ["github.com", ""])
    assert_equal "", Fallback.new(remote, local, true).token("github.com", "")
  end
end
