require_relative "helper"

describe Can do
  let(:can) { Can.new }

  it "lets only rw run passwd" do
    assert can.allow?(profile: "rw", command: "passwd")
    refute can.allow?(profile: "ro", command: "passwd")
  end

  it "lets only rw set a profile" do
    assert can.allow?(profile: "rw", command: "trust", args: ["ancestor"])
    refute can.allow?(profile: "ro", command: "trust", args: ["ancestor"])
  end

  it "lets any profile watch its own ancestor" do
    assert can.allow?(profile: "ro", command: "watch", args: ["ancestor"])
  end

  it "keeps ro from watching a process outside its chain" do
    refute can.allow?(profile: "ro", command: "watch", args: ["other"])
  end

  it "lets rw watch any process" do
    assert can.allow?(profile: "rw", command: "watch", args: ["other"])
  end

  it "allows a command it has no rule for" do
    assert can.allow?(profile: "ro", command: "get")
  end
end
