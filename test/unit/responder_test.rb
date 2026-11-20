require_relative "helper"

describe Responder do
  let(:vault) { Minitest::Mock.new }
  let(:responder) { Responder.new(vault) }

  it "answers a get with the login for the caller's profile" do
    vault.expect(:open, 0)
    vault.expect(:item, "granular:ro:github.com", ["ro", "github.com"])
    vault.expect(:login, "me tok note", ["granular:ro:github.com", ""])
    assert_equal "ok me tok note", responder.reply_for("get github.com", "ro")
    vault.verify
  end

  it "passes the user it was asked for" do
    vault.expect(:open, 0)
    vault.expect(:item, "granular:rw:github.com", ["rw", "github.com"])
    vault.expect(:login, "me tok", ["granular:rw:github.com", "me"])
    assert_equal "ok me tok", responder.reply_for("get github.com me", "rw")
    vault.verify
  end

  it "denies a request that is not a get" do
    assert_equal "deny bad request", responder.reply_for("put github.com", "ro")
    assert_equal "deny bad request", responder.reply_for("get", "ro")
  end

  it "denies when the vault will not open" do
    vault.expect(:open, -1)
    assert_equal "deny no vault", responder.reply_for("get github.com", "ro")
  end

  it "denies when the profile has no item for the host" do
    vault.expect(:open, 0)
    vault.expect(:item, "granular:ro:gitlab.com", ["ro", "gitlab.com"])
    vault.expect(:login, "", ["granular:ro:gitlab.com", ""])
    assert_equal "deny no item ro", responder.reply_for("get gitlab.com", "ro")
  end
end
