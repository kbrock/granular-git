# The daemon's terminal: lists the nodes, flips a node to its next profile, and labels each request's chain.
class Terminal
  def initialize(table, chain)
    @table = table
    @chain = chain
    # The profiles a flip cycles through, in order. The terminal adds to the end.
    @profiles = ["ro", "rw"]
  end

  # The whole chain on one line, outermost first: "login > zsh [2] > claude [1] ro > git". A process that
  # can carry a profile shows its slot number. The process that decided shows the profile after its name.
  # When the root decided, it leads the line: "root [0] ro > zsh > git".
  def chain_label(pid, profile)
    chain = @chain.ancestors(pid)
    return "(unknown caller)" if chain.length == 0
    label = ""
    label = "root [0] #{profile}" if @table.decider == 0
    j = chain.length - 1
    while j >= 0
      if chain[j] > 1
        name = @chain.name(chain[j])
        if !(j == 0 && name == "granular")
          n = @table.node_index(chain[j])
          name = "#{name} [#{n}]" if n >= 0
          name = "#{name} #{profile}" if chain[j] == @table.decider
          label = (label == "") ? name : label + " > " + name
        end
      end
      j -= 1
    end
    label
  end

  def show
    @table.scan_claudes
    home = ENV["HOME"]
    i = 0
    while i < @table.nodes.length
      if i == 0
        warn "  0: root  #{@table.nodes[0].profile}"
      elsif @table.nodes[i].pid == -1 && @table.nodes[i].name != ""
        warn "  #{i}: #{@table.nodes[i].name}  #{@table.nodes[i].profile}"
      elsif !@table.nodes[i].free?
        now = @table.profile_for(@table.nodes[i].pid)
        cwd = G.granular_pid_cwd(@table.nodes[i].pid)
        cwd = "~" + cwd[home.length..] if cwd.start_with?(home)
        warn "  #{i}: #{@chain.name(@table.nodes[i].pid)} pid=#{@table.nodes[i].pid} #{now}  #{cwd}"
      end
      i += 1
    end
  end

  # A node number moves that node to the next profile. A new profile name is added to the end of the list.
  # Anything else lists the nodes.
  def node_command(line)
    nodes = @table.nodes
    @table.scan_claudes
    word = line.strip
    n = word.to_i
    n = -1 if n == 0 && word != "0"
    if n >= 0 && n < nodes.length && !nodes[n].free?
      nodes[n].profile = next_profile((nodes[n].pid > 0) ? @table.profile_for(nodes[n].pid) : nodes[n].profile)
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
