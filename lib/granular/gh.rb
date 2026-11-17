# Installed as "gh" ahead of the real one on PATH: gets the caller's token from the daemon and
# runs the real gh with it in GH_TOKEN.
#
# gh auth runs without the token. Plain `gh auth status` runs with it: gh shows the token masked, and
# any extra argument (--show-token, -t) keeps it bare. `gh auth token` is refused with the profile's
# message: the claude code cli asks for the token to call the API itself, and granular does not hand
# it over.
class Gh
  # The gh that the wrapper runs. `brew unlink gh` leaves it here and takes it off PATH.
  REAL_GH = "/opt/homebrew/opt/gh/bin/gh"

  def initialize(source)
    @source = source
  end

  def run(args:)
    if args[0] == "auth" && args[1] == "token"
      held = login_parts(@source.token("github.com", ""))
      note = (held.length == 3 && held[2] != "") ? " " + held[2] : ""
      warn "gh: granular holds the token and does not print it.#{note}"
      return 1
    end
    if args[0] == "auth" && !(args.length == 2 && args[1] == "status")
      G.granular_exec(REAL_GH, "GH_TOKEN", "")
      warn "gh: cannot run #{REAL_GH}"
      return 1
    end
    reply = @source.token("github.com", "")
    login = login_parts(reply)
    if login.length != 3
      warn "gh: #{(reply == "") ? "no reply from daemon" : reply}"
      return 1
    end
    warn "granular: " + login[2] if args[0] == "auth" && login[2] != ""
    G.granular_exec(REAL_GH, "GH_TOKEN", login[1])
    warn "gh: cannot run #{REAL_GH}"
    1
  end
end
