require_relative "helper"

describe Table do
  let(:world) { World.standard }
  let(:table) { Table.new(Chain.new) }

  before { G.double = world }

  describe "the walk" do
    it "gives a claude and what it starts ro" do
      assert_equal "ro", table.profile_for(103)
      assert_equal 102, table.decider
    end

    it "gives a shell under login rw" do
      world.add(120, 100, "/bin/bash").add(121, 120, "/usr/bin/git")
      assert_equal "rw", table.profile_for(121)
      assert_equal 100, table.decider
    end

    it "gives the root profile when no rule matches" do
      world.add(200, 1, "/bin/foo")
      assert_equal "ro", table.profile_for(200)
      assert_equal 0, table.decider
    end

    it "stops at a process whose path cannot be read" do
      world.add(201, 100, "")
      assert_equal "ro", table.profile_for(201)
    end

    it "gives the root profile to a chain that never reaches pid 0" do
      world.add(7, 99, "/bin/x")
      assert_equal "ro", table.profile_for(7)
    end
  end

  describe "watching" do
    it "keeps the profile a process has now" do
      assert table.watch(101)
      assert_equal "rw", table.profile_for(101)
      table.set_rule("/usr/bin/login", "ro")
      assert_equal "rw", table.profile_for(101)
    end

    it "does not watch a process twice" do
      table.watch(101)
      table.watch(101)
      assert_equal 1, table.watched.length
    end

    it "refuses a process that is not running" do
      refute table.watch(999)
    end

    it "gives a watched process the profile it was set to" do
      assert_equal 0, table.set_profile(101, "ro")
      assert_equal "ro", table.profile_for(101)
      assert_equal "ro", table.profile_for(103)
    end

    it "does not set the profile of a process that is not running" do
      assert_equal(-1, table.set_profile(999, "rw"))
    end

    it "forgets a process that exited" do
      table.watch(101)
      world.remove(101)
      table.forget_gone
      assert_equal 0, table.watched.length
    end

    it "watches every running claude" do
      world.claudes = "102"
      table.scan_claudes
      assert_equal 0, table.watched_index(102)
    end
  end

  describe "rules" do
    it "sets the profile of a rule by name" do
      assert_equal 0, table.set_rule("claude", "rw")
      assert_equal "rw", table.profile_for(103)
    end

    it "refuses a rule that is not there" do
      assert_equal(-1, table.set_rule("nothing", "rw"))
    end
  end

  it "knows a process in the caller's own chain" do
    assert table.ancestor?(103, 101)
    refute table.ancestor?(101, 103)
  end
end
