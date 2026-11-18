# The table of nodes, and the walk that decides a process's profile.
class Table
  # A rule matches a process by name; a name starting with "/" is an executable path, any other name is a
  # file name. A watched process matches by its pid. The walk takes the caller, then its parents. For each
  # process the first match with a profile decides: watched processes first, then the rules from the last
  # to the first. The root rule has pid 0, the parent of launchd, so the walk reaches it last.
  SHELLS = ["sh", "bash", "zsh", "fish", "dash", "ksh", "tcsh"]

  attr_reader :rules, :watched, :decider

  def initialize(chain)
    @chain = chain
    # The pid of the process whose node decided in the last profile_for. 0 means the root rule did.
    @decider = 0
    @rules = [Node.new(0, "", "ro", "")]
    @rules << Node.new(-1, "", "ro", "claude")
    @rules << Node.new(-1, "", "ro", "Claude")
    @rules << Node.new(-1, "", "rw", "/Applications/Sublime Merge.app/Contents/MacOS/sublime_merge")
    @rules << Node.new(-1, "", "rw", "/usr/bin/login")
    @rules << Node.new(-1, "", "rw", "/usr/libexec/sshd-session")
    @watched = []
  end

  # Position of pid among the watched processes, or -1.
  def watched_index(pid)
    i = 0
    while i < @watched.length
      return i if @watched[i].pid == pid
      i += 1
    end
    -1
  end

  # Starts watching pid, with no profile of its own yet. False if the process is not running.
  def watch(pid)
    return true if watched_index(pid) >= 0
    start = G.granular_pid_start(pid)
    return false if start == ""
    @watched << Node.new(pid, start, "", "")
    true
  end

  # Gives pid a profile of its own, watching it first. -1 if the process is not running.
  def set_profile(pid, profile)
    return -1 unless watch(pid)
    @watched[watched_index(pid)].profile = profile
    0
  end

  # Gives the rule with this name a profile. The root rule has the name "". -1 if there is no such rule.
  def set_rule(name, profile)
    i = 0
    while i < @rules.length
      if @rules[i].name == name
        @rules[i].profile = profile
        return 0
      end
      i += 1
    end
    -1
  end

  # Stops watching the processes that have exited.
  def forget_gone
    kept = []
    i = 0
    while i < @watched.length
      kept << @watched[i] unless @watched[i].gone?
      i += 1
    end
    @watched = kept
  end

  # The profile of the first watched process or rule, from the end, that matches pid whose executable is at
  # path. "" if none has one.
  def match_profile(pid, path)
    i = @watched.length - 1
    while i >= 0
      return @watched[i].profile if @watched[i].profile != "" && @watched[i].match?(pid, path)
      i -= 1
    end
    i = @rules.length - 1
    while i >= 0
      return @rules[i].profile if @rules[i].profile != "" && @rules[i].match?(pid, path)
      i -= 1
    end
    ""
  end

  # The profile for pid. The caller is matched against the table, then its parent, up to pid 0.
  # A matching process is watched if it is not yet, so it can be given a profile. A process whose path
  # cannot be read and has no entry of its own stops the walk with the root profile: it could be a claude
  # whose binary was replaced. When the root decides, the outermost shell is watched. A chain that never
  # reached pid 0 gets the root profile.
  def profile_for(pid)
    chain = @chain.ancestors(pid)
    @decider = 0
    forget_gone
    shell = -1
    j = 0
    while j < chain.length
      path = G.granular_pid_path(chain[j])
      profile = match_profile(chain[j], path)
      if profile != ""
        @decider = chain[j]
        if chain[j] == 0
          watch(shell) if shell != -1
        else
          watch(chain[j])
        end
        return profile
      end
      if path == "" && chain[j] > 0
        watch(chain[j])
        return @rules[0].profile
      end
      shell = chain[j] if SHELLS.include?(File.basename(path))
      j += 1
    end
    watch(shell) if shell != -1
    @rules[0].profile
  end

  # Forgets the claudes that exited and watches every running claude.
  def scan_claudes
    forget_gone
    running = G.granular_claude_pids.split(" ")
    k = 0
    while k < running.length
      watch(running[k].to_i)
      k += 1
    end
  end
end
