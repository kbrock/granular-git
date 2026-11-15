# A node: pid is -1 for none, start is the start time that tells a reused pid apart, profile is "" (not
# set) or a profile name, and name is "" for none.
class Node
  attr_accessor :pid, :start, :profile, :name

  def initialize(pid, start, profile, name)
    @pid = pid
    @start = start
    @profile = profile
    @name = name
  end

  def free?
    @pid == -1 && @name == "" && @profile == ""
  end

  # True if this node is for the process pid, whose executable is at path.
  def match?(pid, path)
    return false if @pid == -1 && @name == ""
    return false if @pid != -1 && @pid != pid
    return false if @name != "" && @name != path && @name != File.basename(path)
    true
  end

  # The process has exited, or its pid was reused.
  def gone?
    @pid > 0 && G.granular_pid_start(@pid) != @start
  end

  def clear
    @pid = -1
    @start = ""
    @profile = ""
  end

  def claim(pid)
    @pid = pid
    @start = G.granular_pid_start(pid)
    @profile = ""
  end
end
