require_relative "helper"

describe Chain do
  it "lists a process and its parents up to pid 0" do
    G.double = World.standard
    assert_equal [103, 102, 101, 100, 1, 0], Chain.new.ancestors(103)
  end

  it "stops when a parent cannot be found" do
    G.double = World.new.add(7, 99, "/bin/x")
    assert_equal [7, 99], Chain.new.ancestors(7)
  end

  it "names a process by its executable's file name" do
    G.double.expect(:granular_pid_path, "/opt/homebrew/bin/claude", [5])
    assert_equal "claude", Chain.new.name(5)
  end

  it "marks a name taken from the path the process started with" do
    G.double.expect(:granular_pid_path, "", [5])
    G.double.expect(:granular_pid_exec, "/tmp/foo", [5])
    assert_equal "?foo", Chain.new.name(5)
  end

  it "names a process with neither path a question mark" do
    G.double.expect(:granular_pid_path, "", [5])
    G.double.expect(:granular_pid_exec, "", [5])
    assert_equal "?", Chain.new.name(5)
  end
end
