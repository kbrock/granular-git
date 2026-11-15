# granular-daemon: answers token requests by the caller's profile, and flips profiles from its terminal.
class Daemon
  def initialize(table:, responder:, verbose:)
    @table = table
    @responder = responder
    @verbose = verbose
    # The profiles a flip cycles through, in order. The daemon terminal adds to the end.
    @profiles = ["ro", "rw"]
  end

  def run
    dir = ENV["HOME"] + "/.granular"
    if G.granular_private_dir(dir) != 0
      warn "granular-daemon: #{dir} is not a private directory of yours"
      return 1
    end
    listener = G.granular_listen(dir + "/sock")
    if listener < 0
      warn "granular-daemon: cannot listen on #{dir}/sock"
      return 1
    end
    warn "granular-daemon: listening on #{dir}/sock" if @verbose

    warn "granular-daemon: type a node number and Enter to select the next profile. Enter alone lists the nodes."
    @table.show
    loop do
      fd = G.granular_accept_or_enter(listener)
      if fd == -2
        node_command(G.granular_last_line)
      elsif fd >= 0
        pid = G.granular_peer_pid(fd)
        request = G.granular_read_line(fd)
        profile = @table.profile_for(pid)
        warn @table.chain_label(pid, profile)
        G.granular_write_line(fd, @responder.reply_for(request, profile))
        G.granular_close(fd)
      end
    end
    0
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
    @table.show
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
