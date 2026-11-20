require_relative "helper"

describe Cli do
  let(:cli) { Cli.new }

  it "knows a distance up" do
    assert cli.distance_up?("-1")
    assert cli.distance_up?("-12")
  end

  it "does not take anything else for a distance" do
    ["-0", "1", "-", "-a", "-1a", ""].each { |w| refute cli.distance_up?(w), w }
  end

  it "prints the version" do
    out, = capture_io { assert_equal 0, cli.run("granular", ["--version"]) }
    assert_equal VERSION + "\n", out
  end

  it "prints usage and returns 2 for arguments that do not fit" do
    _, err = capture_io { assert_equal 2, cli.run("granular-trust", ["x"]) }
    assert_match(/usage: granular-trust/, err)
  end

  it "runs a tool through granular <tool>" do
    out, = capture_io { assert_equal 0, cli.run("granular", ["trust", "--help"]) }
    assert_match(/usage: granular-trust/, out)
  end
end
