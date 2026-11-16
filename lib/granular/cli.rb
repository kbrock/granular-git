# Reads the command line, builds what each tool needs, and calls it with named values.
class Cli
  GRANULAR_USAGE = [
    "usage: granular <git|passwd|daemon|trust|gh> ...   (the same as the link of that name)",
    "       granular --version"
  ]
  GIT_USAGE = [
    "usage: granular-git [-v] <get|store|erase>",
    "       granular-git --version"
  ]
  PASSWD_USAGE = [
    "usage: granular-passwd [-v] <profile> <host> [description]",
    "       granular-passwd [-v] --stdin <profile> <host> [description]   (username and token as two lines on stdin)",
    "       granular-passwd [-v] --rekey <profile> <host> [description]",
    "       granular-passwd [-v] --rekey --all",
    "       granular-passwd [-v] --export <profile> <host>   (username and token as two lines, to a pipe)"
  ]
  DAEMON_USAGE = [
    "usage: granular-daemon [-v]"
  ]
  TRUST_USAGE = [
    "usage: granular-trust   (your parents, one per line: distance up, name, pid)"
  ]

  # Each collaborator is built on first use. A test assigns a stub first: cli.local = LocalStub.new
  attr_writer :chain, :vault, :table, :responder, :socket, :remote, :local

  def chain
    @chain ||= Chain.new
  end

  def vault
    @vault ||= Vault.new
  end

  def table
    @table ||= Table.new(chain)
  end

  def responder
    @responder ||= Responder.new(vault)
  end

  # The daemon's socket. GRANULAR_SOCKET in the environment replaces the default, for tests.
  def socket
    @socket ||= ENV["GRANULAR_SOCKET"] || ENV["HOME"] + "/.granular/sock"
  end

  def remote
    @remote ||= Remote.new(socket)
  end

  def local
    @local ||= Local.new(table, responder)
  end

  # name is the program as run, args its arguments. Returns the exit status.
  def run(name, args)
    # granular <applet> ...: the same as running through the link of that name.
    if name == "granular" && args.length > 0 && APPLETS.include?(args[0])
      name = (args[0] == "gh") ? "gh" : SELF_PREFIX + args[0]
      args = args[1..]
    end
    return gh_cli(args) if name == "gh"
    program = name.start_with?(SELF_PREFIX) ? name[SELF_PREFIX.length..] : ""
    case program
    when "git" then git_cli(args)
    when "passwd" then passwd_cli(args)
    when "daemon" then daemon_cli(args)
    when "trust" then trust_cli(args)
    else granular_cli(args)
    end
  end

  # git and gh ask granular-daemon, and decide in this process when there is none.
  def token_source
    Fallback.new(remote, local, REQUIRE_DAEMON)
  end

  # Each *_cli parses the arguments its tool takes, calls the tool with named values, and returns the
  # tool's exit status. Arguments that do not fit print the tool's usage and return 2.
  def granular_cli(args)
    return 0 if version?(args) || help?(args, GRANULAR_USAGE)
    misuse(GRANULAR_USAGE)
  end

  def gh_cli(args)
    Gh.new(token_source).run(args: args)
  end

  def git_cli(args)
    args = args[1..] if args[0] == "-v"
    return 0 if version?(args)
    return misuse(GIT_USAGE) unless args.length == 1
    Git.new(token_source).run(action: args[0])
  end

  def passwd_cli(args)
    verbose = args[0] == "-v"
    args = args[1..] if verbose
    return 0 if version?(args) || help?(args, PASSWD_USAGE)
    passwd = Passwd.new(can: Can.new, vault: vault, caller_profile: table.profile_for(G.getpid), verbose: verbose)
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
      misuse(PASSWD_USAGE)
    end
  end

  def daemon_cli(args)
    verbose = args[0] == "-v"
    args = args[1..] if verbose
    return 0 if version?(args) || help?(args, DAEMON_USAGE)
    return misuse(DAEMON_USAGE) unless args.length == 0
    Daemon.new(table: table, responder: responder, socket: socket, verbose: verbose).run
  end

  def trust_cli(args)
    args = args[1..] if args[0] == "-v"
    return 0 if version?(args) || help?(args, TRUST_USAGE)
    return misuse(TRUST_USAGE) unless args.length == 0
    Trust.new(chain).run
  end

  # true after printing the version, when that is all args asks for.
  def version?(args)
    return false unless args.length == 1 && args[0] == "--version"
    puts VERSION
    true
  end

  # true after printing usage, when that is all args asks for.
  def help?(args, usage)
    return false if args.length != 1
    return false if args[0] != "-h" && args[0] != "--help"
    usage.each { |l| puts l }
    true
  end

  def misuse(usage)
    usage.each { |l| warn l }
    2
  end
end
