# The daemon's terminal: lists the nodes, flips a node to its next profile, and labels each request's chain.
class Terminal
  # The line for a request ends before the first of these.
  CUT = ["git", "git-remote-http", "git-remote-https"]

  def initialize(table, chain)
    @table = table
    @chain = chain
    # The profiles a flip cycles through, in order. The terminal adds to the end.
    @profiles = ["ro", "rw"]
    # The numbers the tab shows: 0 is the root, then the rules, then each marked process. A number stays with
    # its process until the process exits, and then the number is free again.
    @listed = []
    i = 0
    while i < table.rules.length
      @listed << table.rules[i]
      i += 1
    end
  end

  # Gives a number to each watched process that has none.
  def sync
    j = 0
    while j < @table.watched.length
      node = @table.watched[j]
      place(node) unless listed?(node)
      j += 1
    end
  end

  def listed?(node)
    i = @listed.length - 1
    while i >= 0
      return true if @listed[i].pid == node.pid && @listed[i].start == node.start
      i -= 1
    end
    false
  end

  # Puts node at the lowest number whose process has exited, or at the end. Returns the number.
  def place(node)
    i = @table.rules.length
    while i < @listed.length
      if @listed[i].gone?
        @listed[i] = node
        return i
      end
      i += 1
    end
    @listed << node
    @listed.length - 1
  end

  # The number of the marked process pid, or -1.
  def number_for(pid)
    sync
    i = @listed.length - 1
    while i >= 0
      return i if @listed[i].pid == pid && !@listed[i].gone?
      i -= 1
    end
    -1
  end

  # The line logged for a request. When a marked process decides, it is the whole line: "bash [8] rw".
  # Otherwise the chain, outermost first, ending before the first git (or its helpers), with a run of
  # processes of one name shown as its outermost: "login > bash > claude ro". A marked process shows its
  # number, and the process that decided shows the profile after its name. When the root decided, the line
  # leads with "root [0] ro". tool is the granular tool that asked ("trust"), shown last; "" for git and gh.
  def chain_label(pid, profile, tool)
    chain = @chain.ancestors(pid)
    return "(unknown caller)" if chain.length == 0
    decider = @table.decider
    return "#{@chain.name(decider)} [#{number_for(decider)}] #{profile}" if decider > 0 && @table.watched_index(decider) >= 0
    label = ""
    label = "root [0] #{profile}" if decider == 0
    j = chain.length - 1
    while j >= 0
      name = @chain.name(chain[j])
      break if CUT.include?(name)
      if chain[j] > 1 && !(j < chain.length - 1 && name == @chain.name(chain[j + 1]))
        if j == 0 && name == "granular"
          name = (tool == "") ? "" : "granular-" + tool
        else
          n = number_for(chain[j])
          name = "#{name} [#{n}]" if n >= 0
          name = "#{name} #{profile}" if chain[j] == decider
        end
        label = (label == "") ? name : label + " > " + name unless name == ""
      end
      j -= 1
    end
    label
  end

  # The process and where it runs, for the log: "claude 85199 ~/src/granular-git".
  def process_label(pid)
    "#{@chain.name(pid)} #{pid} #{directory(pid)}"
  end

  # The working directory of pid, with the home directory as "~".
  def directory(pid)
    home = ENV["HOME"]
    cwd = G.granular_pid_cwd(pid)
    cwd.start_with?(home) ? "~" + cwd[home.length..] : cwd
  end

  def show
    @table.scan_claudes
    sync
    i = 0
    while i < @listed.length
      node = @listed[i]
      if i == 0
        warn "  0: root  #{node.profile}"
      elsif node.pid == -1
        warn "  #{i}: #{File.basename(node.name)}  #{node.profile}"
      elsif @table.watched_index(node.pid) >= 0 && !node.gone?
        now = @table.profile_for(node.pid)
        warn "  #{i}: #{@chain.name(node.pid)} pid=#{node.pid} #{now}  #{directory(node.pid)}"
      end
      i += 1
    end
  end

  # A node number moves that node to the next profile. A new profile name is added to the end of the list.
  # Anything else lists the nodes.
  def node_command(line)
    @table.scan_claudes
    sync
    word = line.strip
    n = word.to_i
    n = -1 if n == 0 && word != "0"
    if n >= 0 && n < @listed.length
      node = @listed[n]
      if node.pid > 0
        @table.set_profile(node.pid, next_profile(@table.profile_for(node.pid))) unless node.gone?
      else
        @table.set_rule(node.name, next_profile(node.profile))
      end
    elsif profile_name?(word) && !known_profile?(word)
      @profiles << word
    end
    show
  end

  # The profile after name in the profiles, wrapping around. The first if name is not in the list.
  def next_profile(name)
    i = 0
    while i < @profiles.length
      return @profiles[(i + 1) % @profiles.length] if @profiles[i] == name
      i += 1
    end
    @profiles[0]
  end

  # True for a new profile name: starts with a letter, then letters, digits, - or _.
  def profile_name?(word)
    letters = "abcdefghijklmnopqrstuvwxyz"
    return false if word == ""
    return false unless letters.include?(word[0])
    i = 1
    while i < word.length
      return false unless (letters + "0123456789-_").include?(word[i])
      i += 1
    end
    true
  end

  def known_profile?(name)
    i = 0
    while i < @profiles.length
      return true if @profiles[i] == name
      i += 1
    end
    false
  end
end
