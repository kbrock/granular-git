require_relative "helper"

describe Wire do
  it "asks for a host" do
    assert_equal "get github.com", Wire.request_for("github.com", "")
  end

  it "asks for a host and user" do
    assert_equal "get github.com me", Wire.request_for("github.com", "me")
  end

  it "asks the daemon to watch a process" do
    assert_equal "trust 12", Wire.trust_request(12, "")
  end

  it "asks the daemon to give a process a profile" do
    assert_equal "trust 12 rw", Wire.trust_request(12, "rw")
  end

  it "splits an ok reply into user, token and description" do
    assert_equal ["me", "tok", "a note"], Wire.login_parts("ok me tok a note")
  end

  it "gives an empty description when the reply has none" do
    assert_equal ["me", "tok", ""], Wire.login_parts("ok me tok")
  end

  it "gives no parts for a deny" do
    assert_equal [], Wire.login_parts("deny no item ro")
  end

  it "gives no parts for a short ok" do
    assert_equal [], Wire.login_parts("ok me")
  end
end
