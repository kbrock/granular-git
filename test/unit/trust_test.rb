require_relative "helper"

describe Trust do
  let(:world) { World.standard.add(150, 101, "/usr/local/bin/granular") }
  let(:remote) { Minitest::Mock.new }
  let(:trust) { Trust.new(Chain.new, remote) }

  before do
    world.me = 150
    G.double = world
  end

  describe "mark" do
    it "asks the daemon to watch the parent" do
      remote.expect(:ask, "ok", ["trust 101"])
      out, = capture_io { assert_equal 0, trust.mark(distance: 1, profile: "") }
      assert_equal "bash  101  watched\n", out
      remote.verify
    end

    it "asks the daemon to give the parent a profile" do
      remote.expect(:ask, "ok", ["trust 100 rw"])
      out, = capture_io { assert_equal 0, trust.mark(distance: 2, profile: "rw") }
      assert_equal "login  100  rw\n", out
    end

    it "says when there is no daemon" do
      remote.expect(:ask, "down", ["trust 101"])
      _, err = capture_io { assert_equal 1, trust.mark(distance: 1, profile: "") }
      assert_equal "granular-trust: no daemon is running\n", err
    end

    it "says when the daemon does not answer" do
      remote.expect(:ask, "", ["trust 101"])
      _, err = capture_io { trust.mark(distance: 1, profile: "") }
      assert_equal "granular-trust: no reply from daemon\n", err
    end

    it "passes on the daemon's reason for a deny" do
      remote.expect(:ask, "deny trust is not allowed for ro", ["trust 101 rw"])
      _, err = capture_io { assert_equal 1, trust.mark(distance: 1, profile: "rw") }
      assert_equal "granular-trust: deny trust is not allowed for ro\n", err
    end

    it "refuses a distance past the top of the chain" do
      _, err = capture_io { assert_equal 1, trust.mark(distance: 9, profile: "") }
      assert_equal "granular-trust: no process 9 up\n", err
    end

    it "refuses launchd" do
      _, err = capture_io { assert_equal 1, trust.mark(distance: 4, profile: "") }
      assert_match(/no process 4 up/, err)
    end
  end

  it "lists the chain outermost first with the distance up" do
    out, = capture_io { assert_equal 0, trust.run }
    assert_equal "-2  login  100\n-1  bash  101\n0  granular  150\n", out
  end
end
