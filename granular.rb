module G
  ffi_func :getpid,               [],             :int
  ffi_func :granular_parent_pid,  [:int],         :int
  ffi_func :granular_pid_path,    [:int],         :str
  ffi_func :granular_pid_start,   [:int],         :str
  ffi_func :granular_vault,       [:str],         :int
  ffi_func :granular_vault_create, [:str],        :int
  ffi_func :granular_kc_login,    [:str, :str],   :str
  ffi_func :granular_kc_set,      [:str, :str, :str, :str], :int
  ffi_func :granular_read_secret, [:str],         :str
  ffi_func :granular_private_dir, [:str],         :int
  ffi_func :granular_listen,      [:str],         :int
  ffi_func :granular_fetch_socket, [:str],        :int
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
# The profile for claude, and for anything unknown: a chain that does not reach launchd, or a process
# whose executable path cannot be read (for example after its binary was upgraded away).
LOW_PROFILE = "ro"
APP_PROFILES = [LOW_PROFILE, LOW_PROFILE]
DEFAULT_PROFILE = "rw"
# Two stock rows. default: a chain that reaches launchd with no row of its own (pid 1). unknown: a
# chain that does not.
$default_profile = DEFAULT_PROFILE
$unknown_profile = LOW_PROFILE
# git and gh ask granular-daemon. true: with no daemon they give no token. false: they decide in their own process.
REQUIRE_DAEMON = false
# The keychain file in ~/Library/Keychains that holds the logins.
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
  G.granular_vault(ENV["HOME"] + "/Library/Keychains/" + VAULT)
end

def socket_path
  ENV["HOME"] + "/.granular/sock"
end

# The daemon's reply line, "" if it does not answer, "down" if there is no daemon, or a deny if the
# socket is not private to the user.
def ask_daemon(host, user)
  fd = G.granular_fetch_socket(socket_path)
  return "down" if fd == -1
  return "deny socket is not private to you" if fd < 0
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
  if login.length != 3
    $stderr.puts "granular-git: #{reply == "" ? "no reply from daemon" : reply}"
    return 1
  end
  $stderr.puts "granular: " + login[2] unless login[2] == ""
  puts "username=#{login[0]}"
  puts "password=#{login[1]}"
  0
end

# "get <host>", or "get <host> <user>" to pick among several logins for the host.
def request_for(host, user)
  user == "" ? "get " + host : "get " + host + " " + user
end

# ["<user>", "<token>", "<description>"] from an "ok <user> <token> <description words>" reply, with ""
# for no description, and [] for anything else.
def login_parts(reply)
  words = reply.split(" ")
  return [] unless words.length >= 3 && words[0] == "ok"
  [words[1], words[2], words.length > 3 ? words[3..-1].join(" ") : ""]
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
# reach launchd, or holds a process whose path cannot be read, gets the unknown profile.
def profile_for(pid, pids, starts, states)
  chain = ancestors(pid)
  return $unknown_profile unless chain.last == 1
  forget_gone(pids, starts, states)
  shell = -1
  j = 0
  while j < chain.length - 1
    i = node_index(pids, chain[j])
    return states[i] if i >= 0 && states[i] != ""
    return $unknown_profile if G.granular_pid_path(chain[j]) == ""
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
  $default_profile
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
  $stderr.puts "  0: default #{$default_profile}"
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
  if line.strip == "0"
    $default_profile = $default_profile == "rw" ? "ro" : "rw"
  end
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
  $stderr.puts "granular-daemon: type a slot number (0-9) and Enter to flip it between ro and rw. 0 is the default for any process without a slot. Enter alone lists the slots."
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
  if login.length != 3
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

# Checks shared by every granular-passwd form: not under Claude, a known host, the vault is there.
def passwd_ready(host, verbose)
  if locked_above(G.getpid, verbose) != 0
    $stderr.puts "granular-passwd: refusing to run under Claude or an unknown caller"
    return false
  end
  unless HOSTS.include?(host)
    $stderr.puts "granular-passwd: unknown host #{host}"
    return false
  end
  ensure_vault
end

# granular-passwd <profile> <host> [description]: asks for a username and a token.
def passwd_store(args, verbose)
  profile = args[0]
  host = args[1]
  description = args.length == 3 ? args[2] : ""
  return 1 unless passwd_ready(host, verbose)
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
  passwd_write(KEYCHAIN_PREFIX + profile + ":" + host, user, token, description, verbose)
end

# granular-passwd --rekey <profile> <host> [description]: stores the item again with its own user and
# token, so its access list names this build. Without a description the old one is kept.
def passwd_rekey(args, verbose)
  profile = args[1]
  host = args[2]
  return 1 unless passwd_ready(host, verbose)
  item = KEYCHAIN_PREFIX + profile + ":" + host
  words = G.granular_kc_login(item, "").split(" ")
  if words.length < 2
    $stderr.puts "granular-passwd: no #{profile} item for #{host}"
    return 1
  end
  description = words.length > 2 ? words[2..-1].join(" ") : ""
  description = args[3] if args.length == 4
  passwd_write(item, words[0], words[1], description, verbose)
end

# Stores the item and reads it back.
def passwd_write(item, user, token, description, verbose)
  if G.granular_kc_set(item, user, token, description) != 0
    $stderr.puts "granular-passwd: keychain write failed"
    return 1
  end
  if G.granular_kc_login(item, user) != user + " " + token + (description == "" ? "" : " " + description)
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
USAGE = [
  "usage: granular-git [-v] <get|store|erase>",
  "       granular-daemon [-v]",
  "       granular-passwd [-v] <profile> <host> [description]",
  "       granular-passwd [-v] --rekey <profile> <host> [description]"
]
if args.length == 1 && (args[0] == "-h" || args[0] == "--help") && program != "git"
  USAGE.each { |l| puts l }
  exit 0
end
if program == "git" && args.length == 1
  exit git_helper(args[0])
elsif program == "passwd" && (args.length == 3 || args.length == 4) && args[0] == "--rekey"
  exit passwd_rekey(args, verbose)
elsif program == "passwd" && (args.length == 2 || args.length == 3)
  exit passwd_store(args, verbose)
elsif program == "daemon" && args.length == 0
  exit daemon(verbose)
end
USAGE.each { |l| $stderr.puts l }
exit 2
