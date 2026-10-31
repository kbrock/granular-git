module G
  ffi_func :getpid,               [],             :int
  ffi_func :granular_parent_pid,  [:int],         :int
  ffi_func :granular_pid_path,    [:int],         :str
  ffi_func :granular_pid_start,   [:int],         :str
  ffi_func :granular_vault,       [:str],         :int
  ffi_func :granular_vault_create, [:str],        :int
  ffi_func :granular_kc_login,    [:str, :str],   :str
  ffi_func :granular_kc_set,      [:str, :str, :str], :int
  ffi_func :granular_read_secret, [:str],         :str
  ffi_func :granular_private_dir, [:str],         :int
  ffi_func :granular_listen,      [:str],         :int
  ffi_func :granular_connect,     [:str],         :int
  ffi_func :granular_accept,      [:int],         :int
  ffi_func :granular_accept_or_enter, [:int],     :int
  ffi_func :granular_last_line,   [],             :str
  ffi_func :granular_claude_pids, [],             :str
  ffi_func :granular_pid_cwd,     [:int],         :str
  ffi_func :granular_close,       [:int],         :int
  ffi_func :granular_exec,        [:str, :str, :str], :int
  ffi_func :granular_peer_pid,    [:int],         :int
  ffi_func :granular_read_line,   [:int],         :str
  ffi_func :granular_write_line,  [:int, :str],   :int
end

SELF_PREFIX = "granular-"
# A login is a Keychain item: service "granular:<profile>:<host>", account = username, secret = token.
KEYCHAIN_PREFIX = "granular:"

MAX_DEPTH = 64
HOSTS = ["github.com"]
SHELLS = ["sh", "bash", "zsh", "fish", "dash", "ksh", "tcsh"]
# App rows, matched by the executable's file name: the claude CLI and Claude.app. The nearest process
# above the caller with a row decides.
APP_NAMES = ["claude", "Claude"]
APP_PROFILES = ["ro", "ro"]
DEFAULT_PROFILE = "rw"
# git and gh ask granular-daemon. true: with no daemon they give no token. false: they decide in their own process.
REQUIRE_DAEMON = false
# The keychain file in ~/Library/Keychains that holds the logins. Empty uses the login keychain instead.
VAULT = "granular.keychain-db"
# The gh that the wrapper runs. `brew unlink gh` leaves it here and takes it off PATH.
REAL_GH = "/opt/homebrew/opt/gh/bin/gh"

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

# The app row for pid's executable file name, or -1 if it has no row.
def app_row(pid)
  name = File.basename(G.granular_pid_path(pid))
  i = 0
  while i < APP_NAMES.length
    return i if APP_NAMES[i] == name
    i += 1
  end
  -1
end

# 1 if an app row is in pid's ancestry, 0 if not, -1 if the walk fails.
def locked_above(pid, verbose)
  chain = ancestors(pid)
  i = 0
  while i < chain.length
    row = app_row(chain[i])
    path = G.granular_pid_path(chain[i])
    $stderr.puts "walk pid=#{chain[i]} path=#{path == "" ? "(none)" : path}" if verbose
    return 1 if row >= 0
    i += 1
  end
  chain.last == 1 ? 0 : -1
end

# Points the Keychain calls at the vault. 0 if it is open, -1 if the file is missing.
def open_vault
  return 0 if VAULT == ""
  G.granular_vault(ENV["HOME"] + "/Library/Keychains/" + VAULT)
end

def socket_path
  ENV["HOME"] + "/.granular/sock"
end

# The daemon's reply line, "" if it does not answer, or "down" if it cannot be reached.
def ask_daemon(host, user)
  fd = G.granular_connect(socket_path)
  return "down" if fd < 0
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

def reply_for(request, profile)
  words = request.split(" ")
  return "deny bad request" unless (words.length == 2 || words.length == 3) && words[0] == "get"
  return "deny unknown host" unless HOSTS.include?(words[1])

  return "deny no vault" if open_vault != 0
  login = G.granular_kc_login(KEYCHAIN_PREFIX + profile + ":" + words[1], words.length == 3 ? words[2] : "")
  return "deny no item" if login == ""
  "ok " + login
end

# The reply line for a host, from the daemon or decided in this process.
def token_reply(host, user)
  reply = ask_daemon(host, user)
  return reply unless reply == "down"
  return "" if REQUIRE_DAEMON
  reply_for(request_for(host, user), profile_for(G.getpid, [0, 0, 0, 0, 0, 0, 0, 0, 0], ["", "", "", "", "", "", "", "", ""], ["", "", "", "", "", "", "", "", ""]))
end

# Pids in chain (caller first) whose executable is claude.
# Position of pid in pids, or -1.
def node_index(pids, pid)
  i = 0
  while i < pids.length
    return i if pids[i] == pid
    i += 1
  end
  -1
end

# Nine slots remember the claude processes seen. pids[i] is 0 for a free slot, starts[i] is the start
# time that tells a reused pid apart, and states[i] is "" (not set), "ro" or "rw".
def forget_gone(pids, starts, states)
  i = 0
  while i < pids.length
    if pids[i] != 0 && G.granular_pid_start(pids[i]) != starts[i]
      pids[i] = 0
      starts[i] = ""
      states[i] = ""
    end
    i += 1
  end
end

# The lowest free slot now holding pid, or -1 if all are taken.
def claim_slot(pids, starts, states, pid)
  i = 0
  while i < pids.length
    if pids[i] == 0
      pids[i] = pid
      starts[i] = G.granular_pid_start(pid)
      states[i] = ""
      return i
    end
    i += 1
  end
  -1
end

# The daemon's profile for pid. Walking up from the caller, the first process with a profile of its own
# decides: its slot if one is set, else its app row. With none the default applies. The outermost shell
# takes a slot when nothing matched, so a person's terminal can be flipped too. A chain that does not
# reach launchd gets ro.
def profile_for(pid, pids, starts, states)
  chain = ancestors(pid)
  return "ro" unless chain.last == 1
  forget_gone(pids, starts, states)
  shell = -1
  j = 0
  while j < chain.length - 1
    i = node_index(pids, chain[j])
    return states[i] if i >= 0 && states[i] != ""
    row = app_row(chain[j])
    if row >= 0
      claim_slot(pids, starts, states, chain[j]) if i < 0
      return APP_PROFILES[row]
    end
    shell = chain[j] if SHELLS.include?(File.basename(G.granular_pid_path(chain[j])))
    j += 1
  end
  if shell != -1 && node_index(pids, shell) < 0
    claim_slot(pids, starts, states, shell)
  end
  DEFAULT_PROFILE
end

# The whole chain on one line, outermost first and without launchd: "login > zsh [2] > claude [1] > git".
# A process that can carry a profile shows its slot number.
def chain_label(pid, pids)
  chain = ancestors(pid)
  return "(unknown caller)" if chain.length == 0
  label = ""
  j = chain.length - 1
  while j >= 0
    if chain[j] != 1
      name = File.basename(G.granular_pid_path(chain[j]))
      name = "?" if name == ""
      n = node_index(pids, chain[j])
      name = "#{name} [#{n + 1}]" if n >= 0
      label = label == "" ? name : label + " > " + name
    end
    j -= 1
  end
  label
end

# Frees slots of claudes that exited and gives a slot to every running claude that has none.
def scan_claudes(pids, starts, states)
  forget_gone(pids, starts, states)
  running = G.granular_claude_pids.split(" ")
  k = 0
  while k < running.length
    pid = running[k].to_i
    claim_slot(pids, starts, states, pid) if node_index(pids, pid) < 0
    k += 1
  end
end

def show_nodes(pids, starts, states)
  scan_claudes(pids, starts, states)
  home = ENV["HOME"]
  shown = 0
  i = 0
  while i < pids.length
    if pids[i] != 0
      now = profile_for(pids[i], pids, starts, states)
      cwd = G.granular_pid_cwd(pids[i])
      cwd = "~" + cwd[home.length..-1] if cwd.start_with?(home)
      $stderr.puts "  #{i + 1}: #{File.basename(G.granular_pid_path(pids[i]))} pid=#{pids[i]} #{now}  #{cwd}"
      shown += 1
    end
    i += 1
  end
  $stderr.puts "granular-daemon: nothing to flip yet" if shown == 0
end

# A slot number flips that claude between ro and rw. Anything else lists them.
def node_command(line, pids, starts, states)
  scan_claudes(pids, starts, states)
  n = line.to_i
  if n >= 1 && n <= pids.length && pids[n - 1] != 0
    states[n - 1] = profile_for(pids[n - 1], pids, starts, states) == "rw" ? "ro" : "rw"
  end
  show_nodes(pids, starts, states)
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

  pids = [0, 0, 0, 0, 0, 0, 0, 0, 0]
  starts = ["", "", "", "", "", "", "", "", ""]
  states = ["", "", "", "", "", "", "", "", ""]
  $stderr.puts "granular-daemon: type a slot number (1-9) and Enter to flip it between ro and rw. Enter alone lists the slots."
  show_nodes(pids, starts, states)
  while true
    fd = G.granular_accept_or_enter(listener)
    if fd == -2
      node_command(G.granular_last_line, pids, starts, states)
    elsif fd >= 0
      pid = G.granular_peer_pid(fd)
      request = G.granular_read_line(fd)
      profile = profile_for(pid, pids, starts, states)
      $stderr.puts "granular-daemon: #{chain_label(pid, pids)}: #{profile}"
      G.granular_write_line(fd, reply_for(request, profile))
      G.granular_close(fd)
    end
  end
  0
end

# Installed as "gh" ahead of the real one on PATH: gets the caller's token from the daemon and
# runs the real gh with it in GH_TOKEN.
def gh_wrapper
  if ARGV[0] == "auth"
    G.granular_exec(REAL_GH, "GH_TOKEN", "")
    $stderr.puts "gh: cannot run #{REAL_GH}"
    return 1
  end
  reply = token_reply("github.com", "")
  login = login_parts(reply)
  if login.length != 2
    $stderr.puts "gh: #{reply == "" ? "no reply from daemon" : reply}"
    return 1
  end
  G.granular_exec(REAL_GH, "GH_TOKEN", login[1])
  $stderr.puts "gh: cannot run #{REAL_GH}"
  1
end

# Opens the vault, creating it first if the file is missing. False if it cannot.
def ensure_vault
  return true if open_vault == 0
  path = ENV["HOME"] + "/Library/Keychains/" + VAULT
  $stderr.puts "granular-passwd: creating #{path}. A dialog asks for its password."
  if G.granular_vault_create(path) != 0 || open_vault != 0
    $stderr.puts "granular-passwd: cannot create #{path}"
    return false
  end
  true
end

# Copies a login from the login keychain into the vault. The token stays inside this process.
def copy_from_login(profile, host)
  if locked_above(G.getpid, false) != 0
    $stderr.puts "granular-passwd: refusing to run under Claude or an unknown caller"
    return 1
  end
  unless HOSTS.include?(host)
    $stderr.puts "granular-passwd: unknown host #{host}"
    return 1
  end
  if VAULT == ""
    $stderr.puts "granular-passwd: VAULT is empty, so the logins already live in the login keychain"
    return 1
  end
  item = KEYCHAIN_PREFIX + profile + ":" + host
  G.granular_vault("")
  parts = G.granular_kc_login(item, "").split(" ")
  if parts.length != 2
    $stderr.puts "granular-passwd: no #{item} in the login keychain"
    return 1
  end
  return 1 unless ensure_vault
  if G.granular_kc_set(item, parts[0], parts[1]) != 0 || G.granular_kc_login(item, parts[0]) != parts[0] + " " + parts[1]
    $stderr.puts "granular-passwd: vault write failed"
    return 1
  end
  $stderr.puts "granular-passwd: copied #{item} / #{parts[0]} into #{VAULT}"
  $stderr.puts "delete the login keychain copy with: security delete-generic-password -s #{item} -a #{parts[0]}"
  0
end

def passwd(profile, host, verbose)
  if locked_above(G.getpid, verbose) != 0
    $stderr.puts "granular-passwd: refusing to run under Claude or an unknown caller"
    return 1
  end
  unless HOSTS.include?(host)
    $stderr.puts "granular-passwd: unknown host #{host}"
    return 1
  end
  return 1 unless ensure_vault
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
elsif program == "passwd" && args.length == 3 && args[0] == "--from-login"
  exit copy_from_login(args[1], args[2])
elsif program == "daemon" && args.length == 0
  exit daemon(verbose)
end
$stderr.puts "usage: granular-git [-v] <get|store|erase>"
$stderr.puts "       granular-daemon [-v]"
$stderr.puts "       granular-passwd [-v] <profile> <host>"
$stderr.puts "       granular-passwd --from-login <profile> <host>"
exit 2
