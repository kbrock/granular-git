# The daemon's half of the protocol: the reply line for a request line, given the caller's profile.
class Responder
  def initialize(vault)
    @vault = vault
  end

  def reply_for(request, profile)
    words = request.split(" ")
    return "deny bad request" if (words.length != 2 && words.length != 3) || words[0] != "get"
    return "deny no vault" if @vault.open != 0
    login = G.granular_kc_login(KEYCHAIN_PREFIX + profile + ":" + words[1], (words.length == 3) ? words[2] : "")
    return "deny no item " + profile if login == ""
    "ok " + login
  end
end
