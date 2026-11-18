# Decides a token reply in this process, from the table and the vault.
class Local
  def initialize(table, responder)
    @table = table
    @responder = responder
  end

  def token(host, user)
    @responder.reply_for(Wire.request_for(host, user), @table.profile_for(G.getpid))
  end
end
