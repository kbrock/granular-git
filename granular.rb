module G
  ffi_func :getpid,               [],             :int
  ffi_func :granular_parent_pid,  [:int],         :int
  ffi_func :granular_pid_path,    [:int],         :str
  ffi_func :granular_kc_login,    [:str, :str],   :str
  ffi_func :granular_kc_set,      [:str, :str, :str], :int
  ffi_func :granular_read_secret, [:str],         :str
  ffi_func :granular_private_dir, [:str],         :int
  ffi_func :granular_listen,      [:str],         :int
  ffi_func :granular_connect,     [:str],         :int
  ffi_func :granular_accept,      [:int],         :int
  ffi_func :granular_close,       [:int],         :int
  ffi_func :granular_exec_other,  [:str, :str, :str], :int
  ffi_func :granular_peer_pid,    [:int],         :int
  ffi_func :granular_read_line,   [:int],         :str
  ffi_func :granular_write_line,  [:int, :str],   :int
end

SELF_PREFIX = "granular-"
# A login is a Keychain item: service "granular:<profile>:<host>", account = username, secret = token.
KEYCHAIN_PREFIX = "granular:"

MAX_DEPTH = 64
HOSTS = ["github.com"]
# true: git and gh ask granular-daemon. false: each program decides in its own process.
USE_DAEMON = false

# Pids from pid up to launchd. The chain is complete only if it ends at 1.
def ancestors(pid)
  chain = []
  while pid > 0 && chain.length < MAX_DEPTH
    chain << pid
    break if pid == 1
    pid = G.granular_parent_pid(pid)
  end
  chain
end

# 1 if a claude executable is in pid's ancestry, 0 if not, -1 if the walk fails.
def claude_walk(pid, verbose)
  chain = ancestors(pid)
  i = 0
  while i < chain.length
    path = G.granular_pid_path(chain[i])
    $stderr.puts "walk pid=#{chain[i]} path=#{path == "" ? "(none)" : path}" if verbose
    return 1 if File.basename(path) == "claude"
    i += 1
  end
  chain.last == 1 ? 0 : -1
end

def socket_path
  ENV["HOME"] + "/.granular/sock"
end

# The daemon's reply line, or "" if it cannot be reached or does not answer.
def ask_daemon(host, user)
  fd = G.granular_connect(socket_path)
  return "" if fd < 0
  G.granular_write_line(fd, request_for(host, user))
  reply = G.granular_read_line(fd)
  G.granular_close(fd)
  reply
end

def git_helper(action)
  $stderr.puts "granular-git: store ignored" if action == "store"
  return 0 unless action == "get"

  host = ""
  user = ""
  while (line = $stdin.gets)
    line = line.chomp
    break if line == ""
    host = line[5..-1] if line.start_with?("host=")
    user = line[9..-1] if line.start_with?("username=")
  end
  return 0 unless HOSTS.include?(host)

  reply = token_reply(host, user)
  login = login_parts(reply)
  if login.length != 2
    $stderr.puts "granular-git: #{reply == "" ? "no reply from daemon" : reply}"
    return 1
  end
  puts "username=#{login[0]}"
  puts "password=#{login[1]}"
  0
end

# "get <host>", or "get <host> <user>" to pick among several logins for the host.
def request_for(host, user)
  user == "" ? "get " + host : "get " + host + " " + user
end

# ["<user>", "<token>"] from an "ok <user> <token>" reply, [] for anything else.
def login_parts(reply)
  words = reply.split(" ")
  words.length == 3 && words[0] == "ok" ? words[1..2] : []
end

def reply_for(request, pid, verbose)
  words = request.split(" ")
  return "deny bad request" unless (words.length == 2 || words.length == 3) && words[0] == "get"
  return "deny unknown host" unless HOSTS.include?(words[1])

  profile = claude_walk(pid, verbose) == 0 ? "rw" : "ro"
  login = G.granular_kc_login(KEYCHAIN_PREFIX + profile + ":" + words[1], words.length == 3 ? words[2] : "")
  return "deny no item" if login == ""
  "ok " + login
end

# The reply line for a host, from the daemon or decided in this process.
def token_reply(host, user)
  return ask_daemon(host, user) if USE_DAEMON
  reply_for(request_for(host, user), G.getpid, false)
end

def daemon(verbose)
  dir = ENV["HOME"] + "/.granular"
  if G.granular_private_dir(dir) != 0
    $stderr.puts "granular-daemon: #{dir} is not a private directory of yours"
    return 1
  end
  listener = G.granular_listen(dir + "/sock")
  if listener < 0
    $stderr.puts "granular-daemon: cannot listen on #{dir}/sock"
    return 1
  end
  $stderr.puts "granular-daemon: listening on #{dir}/sock" if verbose

  while true
    fd = G.granular_accept(listener)
    if fd >= 0
      pid = G.granular_peer_pid(fd)
      G.granular_write_line(fd, reply_for(G.granular_read_line(fd), pid, verbose))
      G.granular_close(fd)
    end
  end
  0
end

# Installed as "gh" ahead of the real one on PATH: gets the caller's token from the daemon and
# runs the real gh with it in GH_TOKEN.
def gh_wrapper
  if ARGV[0] == "auth"
    G.granular_exec_other("gh", "GH_TOKEN", "")
    $stderr.puts "gh: no other gh found on PATH"
    return 1
  end
  reply = token_reply("github.com", "")
  login = login_parts(reply)
  if login.length != 2
    $stderr.puts "gh: #{reply == "" ? "no reply from daemon" : reply}"
    return 1
  end
  G.granular_exec_other("gh", "GH_TOKEN", login[1])
  $stderr.puts "gh: no other gh found on PATH"
  1
end

def passwd(profile, host, verbose)
  if claude_walk(G.getpid, verbose) != 0
    $stderr.puts "granular-passwd: refusing to run under Claude or an unknown caller"
    return 1
  end
  unless HOSTS.include?(host)
    $stderr.puts "granular-passwd: unknown host #{host}"
    return 1
  end
  $stderr.print "Username: "
  user = ($stdin.gets || "").chomp
  if user == "" || user.include?(" ")
    $stderr.puts "granular-passwd: username must be non-empty with no spaces"
    return 1
  end
  token = G.granular_read_secret("Token: ")
  if token == ""
    $stderr.puts "granular-passwd: no token read"
    return 1
  end

  item = KEYCHAIN_PREFIX + profile + ":" + host
  if G.granular_kc_set(item, user, token) != 0
    $stderr.puts "granular-passwd: keychain write failed"
    return 1
  end
  if G.granular_kc_login(item, user) != user + " " + token
    $stderr.puts "granular-passwd: stored value did not read back"
    return 1
  end
  $stderr.puts "granular-passwd: stored and verified #{token.length} bytes for #{item} / #{user}" if verbose
  0
end

name = File.basename($0)
exit gh_wrapper if name == "gh"
args = ARGV
verbose = false
if args[0] == "-v"
  verbose = true
  args = args[1..-1]
end
program = name.start_with?(SELF_PREFIX) ? name[SELF_PREFIX.length..-1] : ""
if program == "git" && args.length == 1
  exit git_helper(args[0])
elsif program == "passwd" && args.length == 2
  exit passwd(args[0], args[1], verbose)
elsif program == "daemon" && args.length == 0
  exit daemon(verbose)
end
$stderr.puts "usage: granular-git [-v] <get|store|erase>"
$stderr.puts "       granular-daemon [-v]"
$stderr.puts "       granular-passwd [-v] <profile> <host>"
exit 2
