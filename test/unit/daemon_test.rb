require_relative "helper"

describe Daemon do
  let(:table) { Minitest::Mock.new }
  let(:terminal) { Minitest::Mock.new }
  let(:can) { Minitest::Mock.new }
  let(:daemon) { Daemon.new(table: table, responder: nil, terminal: terminal, can: can, socket: "/tmp/x", verbose: false) }

  def allow(answer, command, relation)
    can.expect(:allow?, answer, [], profile: "rw", command: command, args: [relation])
  end

  it "denies a request with too many or too few words" do
    assert_equal "deny bad request", daemon.trust_reply("trust", 50, "rw")
    assert_equal "deny bad request", daemon.trust_reply("trust 1 2 3", 50, "rw")
  end

  it "denies launchd and pid 0" do
    assert_equal "deny bad pid", daemon.trust_reply("trust 1", 50, "rw")
  end

  it "watches a process when Can allows it for the relation" do
    table.expect(:ancestor?, true, [50, 60])
    allow(true, "watch", "ancestor")
    table.expect(:watch, true, [60])
    terminal.expect(:process_label, "bash 60 ~", [60])
    _, err = capture_io { assert_equal "ok", daemon.trust_reply("trust 60", 50, "rw") }
    assert_equal "granular-daemon: watching bash 60 ~\n", err
    [table, terminal, can].each(&:verify)
  end

  it "denies watching when Can refuses" do
    table.expect(:ancestor?, false, [50, 60])
    allow(false, "watch", "other")
    assert_equal "deny watching that process is not allowed for rw", daemon.trust_reply("trust 60", 50, "rw")
  end

  it "denies a process that is gone" do
    table.expect(:ancestor?, true, [50, 60])
    allow(true, "watch", "ancestor")
    table.expect(:watch, false, [60])
    assert_equal "deny process is gone", daemon.trust_reply("trust 60", 50, "rw")
  end

  it "sets a profile when Can allows both and the profile is known" do
    table.expect(:ancestor?, true, [50, 60])
    allow(true, "watch", "ancestor")
    allow(true, "trust", "ancestor")
    terminal.expect(:known_profile?, true, ["rw"])
    table.expect(:set_profile, 0, [60, "rw"])
    terminal.expect(:process_label, "bash 60 ~", [60])
    _, err = capture_io { assert_equal "ok", daemon.trust_reply("trust 60 rw", 50, "rw") }
    assert_equal "granular-daemon: bash 60 ~ set to rw\n", err
  end

  it "denies setting a profile when Can refuses trust" do
    table.expect(:ancestor?, true, [50, 60])
    allow(true, "watch", "ancestor")
    allow(false, "trust", "ancestor")
    assert_equal "deny trust is not allowed for rw", daemon.trust_reply("trust 60 rw", 50, "rw")
  end

  it "denies a profile the tab does not know" do
    table.expect(:ancestor?, true, [50, 60])
    allow(true, "watch", "ancestor")
    allow(true, "trust", "ancestor")
    terminal.expect(:known_profile?, false, ["zzz"])
    assert_equal "deny unknown profile zzz", daemon.trust_reply("trust 60 zzz", 50, "rw")
  end
end
