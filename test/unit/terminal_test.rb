require_relative "helper"

describe Terminal do
  let(:world) { World.standard }
  let(:chain) { Chain.new }
  let(:table) { Table.new(chain) }
  let(:terminal) { Terminal.new(table, chain) }
  let(:first) { table.rules.length }

  before { G.double = world }

  describe "numbers" do
    it "gives a marked process the next number after the rules" do
      table.watch(101)
      assert_equal first, terminal.number_for(101)
    end

    it "gives -1 to a process that is not marked" do
      assert_equal(-1, terminal.number_for(101))
    end

    it "keeps a number with its process" do
      table.watch(101)
      table.watch(102)
      assert_equal first, terminal.number_for(101)
      assert_equal first + 1, terminal.number_for(102)
      assert_equal first, terminal.number_for(101)
    end

    it "reuses the lowest number of a process that exited" do
      table.watch(101)
      table.watch(102)
      terminal.number_for(101)
      terminal.number_for(102)
      world.remove(101)
      world.add(110, 100, "/bin/bash")
      table.watch(110)
      assert_equal first, terminal.number_for(110)
    end
  end

  describe "a number typed in the tab" do
    it "moves a marked process to its next profile" do
      table.watch(101)
      terminal.number_for(101)
      capture_io { terminal.node_command(first.to_s) }
      assert_equal "ro", table.profile_for(101)
    end

    it "moves a rule to its next profile" do
      capture_io { terminal.node_command("1") }
      assert_equal "rw", table.profile_for(103)
    end

    it "adds a new profile name to the end of the cycle" do
      capture_io { terminal.node_command("audit") }
      assert terminal.known_profile?("audit")
      assert_equal "audit", terminal.next_profile("rw")
    end

    it "lists the table for a line that is not a number or a name" do
      _, err = capture_io { terminal.node_command("") }
      assert_match(/0: root  ro/, err)
    end
  end

  describe "profile names" do
    it "wraps around to the first profile" do
      assert_equal "rw", terminal.next_profile("ro")
      assert_equal "ro", terminal.next_profile("rw")
    end

    it "starts at the first for a name it does not know" do
      assert_equal "ro", terminal.next_profile("other")
    end

    it "accepts a letter, then letters, digits, - and _" do
      assert terminal.profile_name?("a-b_2")
      refute terminal.profile_name?("2a")
      refute terminal.profile_name?("")
      refute terminal.profile_name?("a b")
    end
  end

  describe "the label of a request" do
    it "ends the chain before git and shows the profile after the process that decided" do
      profile = table.profile_for(103)
      assert_equal "login > bash > claude ro", terminal.chain_label(103, profile, "")
    end

    it "leads with root when the root rule decided" do
      world.add(200, 1, "/bin/foo").add(201, 200, "/usr/bin/git")
      profile = table.profile_for(201)
      assert_equal "root [0] ro > foo", terminal.chain_label(201, profile, "")
    end

    it "shows a marked process that decided alone, with its number" do
      world.add(120, 101, "/usr/bin/git")
      table.watch(101)
      terminal.number_for(101)
      profile = table.profile_for(120)
      assert_equal "bash [#{first}] rw", terminal.chain_label(120, profile, "")
    end

    it "shows a run of one name as its outermost" do
      world.add(104, 101, "/bin/bash").add(105, 104, "/usr/bin/git")
      profile = table.profile_for(105)
      assert_equal "login rw > bash", terminal.chain_label(105, profile, "")
    end

    it "names the granular tool that asked" do
      world.add(110, 101, "/usr/local/bin/granular")
      profile = table.profile_for(110)
      assert_equal "login rw > bash > granular-trust", terminal.chain_label(110, profile, "trust")
    end
  end

  it "shows a process by name, pid and directory with the home as ~" do
    assert_equal "bash 101 ~/src/app", terminal.process_label(101)
  end
end
