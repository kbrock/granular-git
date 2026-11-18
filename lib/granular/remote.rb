# Asks granular-daemon for a token reply.
class Remote
  def initialize(socket)
    @socket = socket
  end

  # The daemon's reply line, "" if it does not answer, "down" if there is no daemon, or a deny if the
  # socket is not private to the user.
  def token(host, user)
    ask(Wire.request_for(host, user))
  end

  # The same reply line for any request line.
  def ask(line)
    fd = G.granular_fetch_socket(@socket)
    return "down" if fd == -1
    return "deny socket is not private to you" if fd < 0
    G.granular_write_line(fd, line)
    reply = G.granular_read_line(fd)
    G.granular_close(fd)
    reply
  end
end
