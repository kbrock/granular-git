# granular-daemon: answers token requests by the caller's profile, and flips profiles from its terminal.
class Daemon
  def initialize(table:, responder:, terminal:, can:, socket:, verbose:)
    @socket = socket
    @table = table
    @responder = responder
    @terminal = terminal
    @can = can
    @verbose = verbose
  end

  def run
    dir = File.dirname(@socket)
    if G.granular_private_dir(dir) != 0
      warn "granular-daemon: #{dir} is not a private directory of yours"
      return 1
    end
    listener = G.granular_listen(@socket)
    if listener < 0
      warn "granular-daemon: cannot listen on #{@socket}"
      return 1
    end
    warn "granular-daemon: listening on #{@socket}" if @verbose

    warn "granular-daemon: type a node number and Enter to select the next profile. Enter alone lists the nodes."
    @terminal.show
    loop do
      fd = G.granular_accept_or_enter(listener)
      if fd == -2
        @terminal.node_command(G.granular_last_line)
      elsif fd >= 0
        pid = G.granular_peer_pid(fd)
        request = G.granular_read_line(fd)
        profile = @table.profile_for(pid)
        warn @terminal.chain_label(pid, profile, request.start_with?("trust ") ? "trust" : "")
        reply = request.start_with?("trust ") ? trust_reply(request, pid, profile) : @responder.reply_for(request, profile)
        G.granular_write_line(fd, reply)
        G.granular_close(fd)
      end
    end
    0
  end

  # "trust <pid>" watches a process and "trust <pid> <profile>" also gives it the profile, when Can allows
  # it for the caller's profile and the profile is one the tab knows. "ok", or "deny <reason>".
  def trust_reply(request, caller, profile)
    words = request.split(" ")
    return "deny bad request" unless words.length == 2 || words.length == 3
    target = words[1].to_i
    return "deny bad pid" if target <= 1
    relation = @table.ancestor?(caller, target) ? "ancestor" : "other"
    return "deny watching that process is not allowed for " + profile unless @can.allow?(profile: profile, command: "watch", args: [relation])
    if words.length == 3
      return "deny trust is not allowed for " + profile unless @can.allow?(profile: profile, command: "trust", args: [relation])
      return "deny unknown profile " + words[2] unless @terminal.known_profile?(words[2])
      return "deny process is gone" if @table.set_profile(target, words[2]) != 0
      warn "granular-daemon: #{@terminal.process_label(target)} set to #{words[2]}"
    else
      return "deny process is gone" unless @table.watch(target)
      warn "granular-daemon: watching #{@terminal.process_label(target)}"
    end
    "ok"
  end
end
