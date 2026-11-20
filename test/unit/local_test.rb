require_relative "helper"

describe Local do
  it "answers with the table's profile for this process" do
    world = World.standard
    world.me = 103
    G.double = world
    responder = Minitest::Mock.new
    responder.expect(:reply_for, "deny no item ro", ["get github.com", "ro"])
    assert_equal "deny no item ro", Local.new(Table.new(Chain.new), responder).token("github.com", "")
    responder.verify
  end
end
