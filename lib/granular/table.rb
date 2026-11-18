# The table of nodes, and the walk that decides a process's profile.
class Table
  # A node matches a process by its pid, if it has one, and by its name, if it has one. A name starting
  # with "/" is an executable path; any other name is a file name. The walk takes the caller, then its
  # parents. For each process the first matching node with a profile, from the bottom of the table up,
  # decides. Node 0 has pid 0, the parent of launchd, so the walk reaches it last. The nodes after the
  # rules are slots, added as processes are claimed.
  MAX_NODES = 32
  SHELLS = ["sh", "bash", "zsh", "fish", "dash", "ksh", "tcsh"]

  attr_reader :nodes, :decider

  def initialize(chain)
    @chain = chain
    # The pid of the process whose node decided in the last profile_for. 0 means the root node did.
    @decider = 0
    @nodes = [Node.new(0, "", "ro", "")]
    @nodes << Node.new(-1, "", "ro", "claude")
    @nodes << Node.new(-1, "", "ro", "Claude")
    @nodes << Node.new(-1, "", "rw", "/Applications/Sublime Merge.app/Contents/MacOS/sublime_merge")
    @nodes << Node.new(-1, "", "rw", "/usr/bin/login")
    @nodes << Node.new(-1, "", "rw", "/usr/libexec/sshd-session")
  end

  # Position of pid among the slots, or -1.
  def node_index(pid)
    i = 0
    while i < @nodes.length
      return i if @nodes[i].pid == pid
      i += 1
    end
    -1
  end

  # Frees the slots whose process has gone.
  def forget_gone
    i = 1
    while i < @nodes.length
      @nodes[i].clear if @nodes[i].gone?
      i += 1
    end
  end

  # The lowest free slot now holding pid, a new node if none is free, or -1 if the table is full.
  def claim_slot(pid)
    i = 1
    while i < @nodes.length
      if @nodes[i].free?
        @nodes[i].claim(pid)
        return i
      end
      i += 1
    end
    return -1 if @nodes.length >= MAX_NODES
    @nodes << Node.new(pid, G.granular_pid_start(pid), "", "")
    @nodes.length - 1
  end

  # The profile for pid. The caller is matched against the table, then its parent, up to pid 0.
  # A matching process takes a slot if it has none, so it can be flipped. A process whose path cannot be
  # read and has no node of its own stops the walk with the root profile: it could be a claude whose
  # binary was replaced. When the root decides, the outermost shell takes a slot so it can be flipped. A
  # chain that never reached pid 0 gets the root profile.
  def profile_for(pid)
    chain = @chain.ancestors(pid)
    @decider = 0
    forget_gone
    shell = -1
    j = 0
    while j < chain.length
      path = G.granular_pid_path(chain[j])
      i = @nodes.length - 1
      while i >= 0
        if @nodes[i].profile != "" && @nodes[i].match?(chain[j], path)
          @decider = chain[j]
          if chain[j] == 0
            claim_slot(shell) if shell != -1 && node_index(shell) < 0
          elsif node_index(chain[j]) < 0
            claim_slot(chain[j])
          end
          return @nodes[i].profile
        end
        i -= 1
      end
      if path == "" && chain[j] > 0
        claim_slot(chain[j]) if node_index(chain[j]) < 0
        return @nodes[0].profile
      end
      shell = chain[j] if SHELLS.include?(File.basename(path))
      j += 1
    end
    claim_slot(shell) if shell != -1 && node_index(shell) < 0
    @nodes[0].profile
  end

  # Frees slots of claudes that exited and gives a slot to every running claude that has none.
  def scan_claudes
    forget_gone
    running = G.granular_claude_pids.split(" ")
    k = 0
    while k < running.length
      pid = running[k].to_i
      claim_slot(pid) if node_index(pid) < 0
      k += 1
    end
  end
end
