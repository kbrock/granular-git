# granular-trust: this process and its parents, one per line, outermost first and without launchd. The
# number is the distance up from this process: 0 is this process, -1 its parent. With a distance and a
# profile it asks granular-daemon to give that parent the profile. With only a distance it asks the daemon
# to watch that parent.
class Trust
  def initialize(chain, remote)
    @chain = chain
    @remote = remote
  end

  # Asks the daemon to watch the process distance up from this one (1 is the parent), and with a profile to
  # give it that profile. The daemon decides.
  def mark(distance:, profile:)
    chain = @chain.ancestors(G.getpid)
    if distance >= chain.length || chain[distance] <= 1
      warn "granular-trust: no process #{distance} up"
      return 1
    end
    pid = chain[distance]
    reply = @remote.ask(Wire.trust_request(pid, profile))
    if reply == "ok"
      puts "#{@chain.name(pid)}  #{pid}  #{(profile == "") ? "watched" : profile}"
      return 0
    end
    message = reply
    message = "no daemon is running" if reply == "down"
    message = "no reply from daemon" if reply == ""
    warn "granular-trust: " + message
    1
  end

  def run
    chain = @chain.ancestors(G.getpid)
    j = chain.length - 1
    while j >= 0
      if chain[j] > 1
        puts "#{(j == 0) ? "0" : "-" + j.to_s}  #{@chain.name(chain[j])}  #{chain[j]}"
      end
      j -= 1
    end
    0
  end
end
