# Whether a profile may run a command. Hardcoded for now; a rules store replaces the body later.
class Can
  def allow?(profile:, command:, args: [])
    return profile == "rw" if command == "passwd"
    true
  end
end
