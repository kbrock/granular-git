# Reads the command line, builds what each tool needs, and calls it with named values.
class Cli
  USAGE = [
    "usage: granular-git [-v] <get|store|erase>",
    "       granular-git --version",
    "       granular-daemon [-v]",
    "       granular-passwd [-v] <profile> <host> [description]",
    "       granular-passwd [-v] --stdin <profile> <host> [description]   (username and token as two lines on stdin)",
    "       granular-passwd [-v] --rekey <profile> <host> [description]",
    "       granular-passwd [-v] --rekey --all",
    "       granular-passwd [-v] --export <profile> <host>   (username and token as two lines, to a pipe)",
    "       granular-trust   (your parents, one per line: distance up, name, pid)",
    "       granular <git|passwd|daemon|trust|gh> ...   (the same, without the link)",
    "       granular --version"
  ]

  def initialize
    @chain = Chain.new
    @vault = Vault.new
  end

  # name is the program as run, args its arguments. Returns the exit status.
  def run(name, args)
    # granular <applet> ...: the same as running through the link of that name.
    if name == "granular" && args.length > 0 && APPLETS.include?(args[0])
      name = (args[0] == "gh") ? "gh" : SELF_PREFIX + args[0]
      args = args[1..]
    end
    return Gh.new(token_source).run(args: args) if name == "gh"
    verbose = false
    if args[0] == "-v"
      verbose = true
      args = args[1..]
    end
    program = name.start_with?(SELF_PREFIX) ? name[SELF_PREFIX.length..] : ""
    if args.length == 1 && args[0] == "--version"
      puts VERSION
      return 0
    end
    if args.length == 1 && (args[0] == "-h" || args[0] == "--help") && program != "git"
      USAGE.each { |l| puts l }
      return 0
    end
    status = -1
    status = parse_git(args) if program == "git"
    status = parse_passwd(args, verbose) if program == "passwd"
    status = parse_daemon(args, verbose) if program == "daemon"
    status = parse_trust(args) if program == "trust"
    return status unless status == -1
    USAGE.each { |l| warn l }
    2
  end

  # git and gh ask granular-daemon, and decide in this process when there is none.
  def token_source
    Fallback.new(Remote.new, Local.new(Table.new(@chain), Responder.new(@vault)), REQUIRE_DAEMON)
  end

  # Each parse_* returns the tool's exit status, or -1 when args do not fit the tool.
  def parse_git(args)
    return -1 unless args.length == 1
    Git.new(token_source).run(action: args[0])
  end

  def parse_passwd(args, verbose)
    passwd = Passwd.new(can: Can.new, vault: @vault, caller_profile: Table.new(@chain).profile_for(G.getpid), verbose: verbose)
    if args.length == 2 && args[0] == "--rekey" && args[1] == "--all"
      passwd.rekey_all
    elsif args.length == 3 && args[0] == "--export"
      passwd.export(profile: args[1], host: args[2])
    elsif (args.length == 3 || args.length == 4) && args[0] == "--rekey"
      passwd.rekey(profile: args[1], host: args[2], description: (args.length == 4) ? args[3] : "", set_description: args.length == 4)
    elsif (args.length == 3 || args.length == 4) && args[0] == "--stdin"
      passwd.store(profile: args[1], host: args[2], description: (args.length == 4) ? args[3] : "", from_stdin: true)
    elsif args.length == 2 || args.length == 3
      passwd.store(profile: args[0], host: args[1], description: (args.length == 3) ? args[2] : "", from_stdin: false)
    else
      -1
    end
  end

  def parse_daemon(args, verbose)
    return -1 unless args.length == 0
    Daemon.new(table: Table.new(@chain), responder: Responder.new(@vault), verbose: verbose).run
  end

  def parse_trust(args)
    return -1 unless args.length == 0
    Trust.new(@chain).run
  end
end
