# granular-daemon: answers token requests by the caller's profile, and flips profiles from its terminal.
class Daemon
  def initialize(table:, responder:, terminal:, socket:, verbose:)
    @socket = socket
    @table = table
    @responder = responder
    @terminal = terminal
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
        warn @terminal.chain_label(pid, profile)
        G.granular_write_line(fd, @responder.reply_for(request, profile))
        G.granular_close(fd)
      end
    end
    0
  end
end
