# A process and its parents.
class Chain
  MAX_DEPTH = 64

  # Pids from pid up to pid 0, the parent of launchd. A chain that does not end at 0 is broken.
  def ancestors(pid)
    chain = []
    while pid >= 0 && chain.length < MAX_DEPTH
      chain << pid
      break if pid == 0
      pid = G.granular_parent_pid(pid)
    end
    chain
  end

  # The executable's file name, for display. When the file can no longer be read, the name from the path
  # the process was started with, after a "?", or just "?" if that is gone too. Never used to decide.
  def name(pid)
    name = File.basename(G.granular_pid_path(pid))
    return name unless name == ""
    started = File.basename(G.granular_pid_exec(pid))
    (started == "") ? "?" : "?" + started
  end
end
