# The daemon protocol: one request line, one reply line.
class Wire
  # "get <host>", or "get <host> <user>" to pick among several logins for the host.
  def self.request_for(host, user)
    (user == "") ? "get " + host : "get " + host + " " + user
  end

  # ["<user>", "<token>", "<description>"] from an "ok <user> <token> <description words>" reply, with ""
  # for no description, and [] for anything else.
  def self.login_parts(reply)
    words = reply.split(" ")
    return [] unless words.length >= 3 && words[0] == "ok"
    [words[1], words[2], (words.length > 3) ? words[3..].join(" ") : ""]
  end
end
