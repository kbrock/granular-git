# Whether a profile may run a command. Hardcoded for now; a rules store replaces the body later.
class Can
  def allow?(profile:, command:, args: [])
    return profile == "rw" if command == "passwd" || command == "trust"
    # watch: args[0] is "ancestor" for a process in the caller's own chain, "other" for any other.
    return profile == "rw" || (args.length == 1 && args[0] == "ancestor") if command == "watch"
    true
  end
end
