# The reply line for a host: the daemon's, or Local's when there is no daemon. With require_daemon
# set, no daemon means no token.
class Fallback
  def initialize(remote, local, require_daemon)
    @remote = remote
    @local = local
    @require_daemon = require_daemon
  end

  def token(host, user)
    reply = @remote.token(host, user)
    return reply unless reply == "down"
    return "" if @require_daemon
    @local.token(host, user)
  end
end
