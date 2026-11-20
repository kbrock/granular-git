require_relative "helper"

describe Node do
  it "matches the process with its pid" do
    assert Node.new(10, "1.1", "ro", "").match?(10, "/bin/bash")
    refute Node.new(10, "1.1", "ro", "").match?(11, "/bin/bash")
  end

  it "matches a name by file name or by full path" do
    node = Node.new(-1, "", "ro", "claude")
    assert node.match?(5, "/opt/homebrew/bin/claude")
    refute node.match?(5, "/opt/homebrew/bin/other")
    assert Node.new(-1, "", "rw", "/usr/bin/login").match?(5, "/usr/bin/login")
    refute Node.new(-1, "", "rw", "/usr/bin/login").match?(5, "/tmp/login")
  end

  it "matches nothing when it has neither a pid nor a name" do
    refute Node.new(-1, "", "ro", "").match?(5, "/bin/bash")
  end

  it "is gone when the process start time changed" do
    G.double.expect(:granular_pid_start, "2.0", [10])
    assert Node.new(10, "1.0", "ro", "").gone?
  end

  it "is not gone while the start time is the same" do
    G.double.expect(:granular_pid_start, "1.0", [10])
    refute Node.new(10, "1.0", "ro", "").gone?
  end

  it "is never gone for a rule" do
    refute Node.new(-1, "", "ro", "claude").gone?
  end
end
