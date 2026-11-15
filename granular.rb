module G
  ffi_func :getpid,               [],             :int
  ffi_func :isatty,               [:int],         :int
  ffi_func :granular_parent_pid,  [:int],         :int
  ffi_func :granular_pid_path,    [:int],         :str
  ffi_func :granular_pid_exec,    [:int],         :str
  ffi_func :granular_pid_start,   [:int],         :str
  ffi_func :granular_vault,       [:str],         :int
  ffi_func :granular_vault_create, [:str],        :int
  ffi_func :granular_kc_login,    [:str, :str],   :str
  ffi_func :granular_kc_set,      [:str, :str, :str, :str], :int
  ffi_func :granular_kc_list_open, [:str],        :int
  ffi_func :granular_kc_list_get, [:int],         :str
  ffi_func :granular_kc_list_close, [],           :int
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

VERSION = "0.2.0"
SELF_PREFIX = "granular-"
# A login is a Keychain item: service "granular:<profile>:<host>", account = username, secret = token.
KEYCHAIN_PREFIX = "granular:"

MAX_DEPTH = 64
# Set by profile_for: the pid of the process whose node decided. 0 means the root node did.
$decider = 0
APPLETS = ["git", "passwd", "daemon", "trust", "gh"]
SHELLS = ["sh", "bash", "zsh", "fish", "dash", "ksh", "tcsh"]
# The table of nodes. A node matches a process by its pid, if it has one, and by its name, if it has one. A
# name starting with "/" is an executable path; any other name is a file name. The walk takes the caller,
# then its parents. For each process the first matching node with a profile, from the bottom of the table
# up, decides. Node 0 has pid 0, the parent of launchd, so the walk reaches it last. The nodes after the
# rules are slots, added as processes are claimed.
MAX_NODES = 32

# A node: pid is -1 for none, start is the start time that tells a reused pid apart, profile is "" (not
# set) or a profile name, and name is "" for none.
class Node
  attr_accessor :pid, :start, :profile, :name

  def initialize(pid, start, profile, name)
    @pid = pid
    @start = start
    @profile = profile
    @name = name
  end

  def free?
    @pid == -1 && @name == "" && @profile == ""
  end

  # True if this node is for the process pid, whose executable is at path.
  def match?(pid, path)
    return false if @pid == -1 && @name == ""
    return false if @pid != -1 && @pid != pid
    return false if @name != "" && @name != path && @name != File.basename(path)
    true
  end

  # The process has exited, or its pid was reused.
  def gone?
    @pid > 0 && G.granular_pid_start(@pid) != @start
  end

  def clear
    @pid = -1
    @start = ""
    @profile = ""
  end

  def claim(pid)
    @pid = pid
    @start = G.granular_pid_start(pid)
    @profile = ""
  end
end

def new_table
  nodes = [Node.new(0, "", "ro", "")]
  nodes << Node.new(-1, "", "ro", "claude")
  nodes << Node.new(-1, "", "ro", "Claude")
  nodes << Node.new(-1, "", "rw", "/Applications/Sublime Merge.app/Contents/MacOS/sublime_merge")
  nodes << Node.new(-1, "", "rw", "/usr/bin/login")
  nodes << Node.new(-1, "", "rw", "/usr/libexec/sshd-session")
  nodes
end

# The profiles a flip cycles through, in order. The daemon terminal adds to the end.
$profiles = ["ro", "rw"]
# git and gh ask granular-daemon. true: with no daemon they give no token. false: they decide in their own process.
REQUIRE_DAEMON = false
# The keychain file in ~/Library/Keychains that holds the logins.
VAULT = "granular.keychain-db"
# The gh that the wrapper runs. `brew unlink gh` leaves it here and takes it off PATH.
REAL_GH = "/opt/homebrew/opt/gh/bin/gh"

# Pids from pid up to pid 0, the parent of launchd. A chain that does not end at 0 is broken.
def ancestors(pid)
  chain = []
  while pid >= 0 && chain.length < MAX_DEPTH
    chain << pid
    break if pid == 0
    pid = G.granular_parent_pid(pid)
  end
  chain
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
  # $stderr.puts "granular-git: store ignored" if action == "store"
  return 0 unless action == "get"

  host = ""
  user = ""
  while (line = $stdin.gets)
    line = line.chomp
    break if line == ""
    host = line[5..-1] if line.start_with?("host=")
    user = line[9..-1] if line.start_with?("username=")
  end
  return 0 if host == ""

  reply = token_reply(host, user)
  if reply.start_with?("deny no item ")
    $stderr.puts "granular: no token for #{host} profile #{reply[13..-1]}"
    return 0
  end
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
  return "deny no vault" if open_vault != 0
  login = G.granular_kc_login(KEYCHAIN_PREFIX + profile + ":" + words[1], words.length == 3 ? words[2] : "")
  return "deny no item " + profile if login == ""
  "ok " + login
end

# The reply line for a host, from the daemon or decided in this process.
def token_reply(host, user)
  reply = ask_daemon(host, user)
  return reply unless reply == "down"
  return "" if REQUIRE_DAEMON
  reply_for(request_for(host, user), profile_for(G.getpid, new_table))
end

# Pids in chain (caller first) whose executable is claude.
# Position of pid among the slots, or -1.
def node_index(nodes, pid)
  i = 0
  while i < nodes.length
    return i if nodes[i].pid == pid
    i += 1
  end
  -1
end

# Frees the slots whose process has gone.
def forget_gone(nodes)
  i = 1
  while i < nodes.length
    nodes[i].clear if nodes[i].gone?
    i += 1
  end
end

# The lowest free slot now holding pid, a new node if none is free, or -1 if the table is full.
def claim_slot(nodes, pid)
  i = 1
  while i < nodes.length
    if nodes[i].free?
      nodes[i].claim(pid)
      return i
    end
    i += 1
  end
  return -1 if nodes.length >= MAX_NODES
  nodes << Node.new(pid, G.granular_pid_start(pid), "", "")
  nodes.length - 1
end

# The daemon's profile for pid. The caller is matched against the table, then its parent, up to pid 0.
# A matching process takes a slot if it has none, so it can be flipped. A process whose path cannot be
# read and has no node of its own stops the walk with the root profile: it could be a claude whose
# binary was replaced. When the root decides, the outermost shell takes a slot so it can be flipped. A
# chain that never reached pid 0 gets the root profile.
def profile_for(pid, nodes)
  chain = ancestors(pid)
  $decider = 0
  forget_gone(nodes)
  shell = -1
  j = 0
  while j < chain.length
    path = G.granular_pid_path(chain[j])
    i = nodes.length - 1
    while i >= 0
      if nodes[i].profile != "" && nodes[i].match?(chain[j], path)
        $decider = chain[j]
        if chain[j] == 0
          claim_slot(nodes, shell) if shell != -1 && node_index(nodes, shell) < 0
        elsif node_index(nodes, chain[j]) < 0
          claim_slot(nodes, chain[j])
        end
        return nodes[i].profile
      end
      i -= 1
    end
    if path == "" && chain[j] > 0
      claim_slot(nodes, chain[j]) if node_index(nodes, chain[j]) < 0
      return nodes[0].profile
    end
    shell = chain[j] if SHELLS.include?(File.basename(path))
    j += 1
  end
  claim_slot(nodes, shell) if shell != -1 && node_index(nodes, shell) < 0
  nodes[0].profile
end

# The executable's file name, for display. When the file can no longer be read, the name from the path
# the process was started with, after a "?", or just "?" if that is gone too. Never used to decide.
def process_name(pid)
  name = File.basename(G.granular_pid_path(pid))
  return name unless name == ""
  started = File.basename(G.granular_pid_exec(pid))
  started == "" ? "?" : "?" + started
end

# The whole chain on one line, outermost first: "login > zsh [2] > claude [1] ro > git". A process that
# can carry a profile shows its slot number. The process that decided shows the profile after its name.
# When the root decided, it leads the line: "root [0] ro > zsh > git".
def chain_label(pid, nodes, profile)
  chain = ancestors(pid)
  return "(unknown caller)" if chain.length == 0
  label = ""
  label = "root [0] #{profile}" if $decider == 0
  j = chain.length - 1
  while j >= 0
    if chain[j] > 1
      name = process_name(chain[j])
      if !(j == 0 && name == "granular")
        n = node_index(nodes, chain[j])
        name = "#{name} [#{n}]" if n >= 0
        name = "#{name} #{profile}" if chain[j] == $decider
        label = label == "" ? name : label + " > " + name
      end
    end
    j -= 1
  end
  label
end

# granular-trust: this process and its parents, one per line, outermost first and without launchd. The
# number is the distance up from this process: 0 is this process, -1 its parent.
def trust_chain
  chain = ancestors(G.getpid)
  j = chain.length - 1
  while j >= 0
    if chain[j] > 1
      puts "#{j == 0 ? "0" : "-" + j.to_s}  #{process_name(chain[j])}  #{chain[j]}"
    end
    j -= 1
  end
  0
end

# Frees slots of claudes that exited and gives a slot to every running claude that has none.
def scan_claudes(nodes)
  forget_gone(nodes)
  running = G.granular_claude_pids.split(" ")
  k = 0
  while k < running.length
    pid = running[k].to_i
    claim_slot(nodes, pid) if node_index(nodes, pid) < 0
    k += 1
  end
end

def show_nodes(nodes)
  scan_claudes(nodes)
  home = ENV["HOME"]
  i = 0
  while i < nodes.length
    if i == 0
      $stderr.puts "  0: root  #{nodes[0].profile}"
    elsif nodes[i].pid == -1 && nodes[i].name != ""
      $stderr.puts "  #{i}: #{nodes[i].name}  #{nodes[i].profile}"
    elsif !nodes[i].free?
      now = profile_for(nodes[i].pid, nodes)
      cwd = G.granular_pid_cwd(nodes[i].pid)
      cwd = "~" + cwd[home.length..-1] if cwd.start_with?(home)
      $stderr.puts "  #{i}: #{process_name(nodes[i].pid)} pid=#{nodes[i].pid} #{now}  #{cwd}"
    end
    i += 1
  end
end

# The profile after name in $profiles, wrapping around. The first if name is not in the list.
def next_profile(name)
  i = 0
  while i < $profiles.length
    return $profiles[(i + 1) % $profiles.length] if $profiles[i] == name
    i += 1
  end
  $profiles[0]
end

# True for a new profile name: starts with a letter, then letters, digits, - or _.
def profile_name?(word)
  letters = "abcdefghijklmnopqrstuvwxyz"
  return false if word == ""
  return false unless letters.include?(word[0])
  i = 1
  while i < word.length
    return false unless (letters + "0123456789-_").include?(word[i])
    i += 1
  end
  true
end

def known_profile?(name)
  i = 0
  while i < $profiles.length
    return true if $profiles[i] == name
    i += 1
  end
  false
end

# A node number moves that node to the next profile. A new profile name is added to the end of the list.
# Anything else lists the nodes.
def node_command(line, nodes)
  scan_claudes(nodes)
  word = line.strip
  n = word.to_i
  n = -1 if n == 0 && word != "0"
  if n >= 0 && n < nodes.length && !nodes[n].free?
    nodes[n].profile = next_profile(nodes[n].pid > 0 ? profile_for(nodes[n].pid, nodes) : nodes[n].profile)
  elsif profile_name?(word) && !known_profile?(word)
    $profiles << word
  end
  show_nodes(nodes)
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

  nodes = new_table
  $stderr.puts "granular-daemon: type a node number and Enter to select the next profile. Enter alone lists the nodes."
  show_nodes(nodes)
  while true
    fd = G.granular_accept_or_enter(listener)
    if fd == -2
      node_command(G.granular_last_line, nodes)
    elsif fd >= 0
      pid = G.granular_peer_pid(fd)
      request = G.granular_read_line(fd)
      profile = profile_for(pid, nodes)
      $stderr.puts chain_label(pid, nodes, profile)
      G.granular_write_line(fd, reply_for(request, profile))
      G.granular_close(fd)
    end
  end
  0
end

# Installed as "gh" ahead of the real one on PATH: gets the caller's token from the daemon and
# runs the real gh with it in GH_TOKEN.
#
# gh auth runs without the token. Plain `gh auth status` runs with it: gh shows the token masked, and
# any extra argument (--show-token, -t) keeps it bare. `gh auth token` is refused with the profile's
# message: the claude code cli asks for the token to call the API itself, and granular does not hand
# it over.
def gh_wrapper(args)
  if args[0] == "auth" && args[1] == "token"
    held = login_parts(token_reply("github.com", ""))
    note = held.length == 3 && held[2] != "" ? " " + held[2] : ""
    $stderr.puts "gh: granular holds the token and does not print it.#{note}"
    return 1
  end
  if args[0] == "auth" && !(args.length == 2 && args[1] == "status")
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
  $stderr.puts "granular: " + login[2] if args[0] == "auth" && login[2] != ""
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

# Checks shared by every granular-passwd form: not under Claude, the vault is there.
def passwd_ready(verbose)
  if profile_for(G.getpid, new_table) != "rw"
    $stderr.puts "granular-passwd: refusing to run under Claude or an unknown caller"
    return false
  end
  ensure_vault
end

# granular-passwd <profile> <host> [description]: asks for a username and a token.
def passwd_store(args, verbose, from_stdin)
  profile = args[0]
  host = args[1]
  description = args.length == 3 ? args[2] : ""
  return 1 unless passwd_ready(verbose)
  $stderr.print "Username: " unless from_stdin
  user = ($stdin.gets || "").chomp
  if user == "" || user.include?(" ")
    $stderr.puts "granular-passwd: username must be non-empty with no spaces"
    return 1
  end
  token = from_stdin ? ($stdin.gets || "").chomp : G.granular_read_secret("Token: ")
  if token == ""
    $stderr.puts "granular-passwd: no token read"
    return 1
  end
  passwd_write(KEYCHAIN_PREFIX + profile + ":" + host, user, token, description, verbose)
end

# granular-passwd --rekey <profile> <host> [description]: stores the item again with its own user and
# token, so its access list names this build. Without a description the old one is kept.
def passwd_rekey(args, verbose, quiet)
  profile = args[1]
  host = args[2]
  return 1 unless passwd_ready(verbose)
  item = KEYCHAIN_PREFIX + profile + ":" + host
  words = G.granular_kc_login(item, "").split(" ")
  if words.length < 2
    $stderr.puts "granular-passwd: no #{profile} item for #{host}" unless quiet
    return quiet ? 2 : 1
  end
  description = words.length > 2 ? words[2..-1].join(" ") : ""
  description = args[3] if args.length == 4
  passwd_write(item, words[0], words[1], description, verbose)
end

# Yields the profile and host of each item in the vault.
def each_item
  n = G.granular_kc_list_open(KEYCHAIN_PREFIX)
  n.times do |i|
    name = G.granular_kc_list_get(i)
    next if name == ""
    rest = name[KEYCHAIN_PREFIX.length..-1]
    colon = rest.index(":")
    yield rest[0, colon], rest[colon + 1..-1] if colon
  end
  G.granular_kc_list_close
end

# granular-passwd --rekey --all: rekeys every item that exists, one prompt each, so they come together.
def passwd_rekey_all(verbose)
  return 1 unless passwd_ready(verbose)
  status = 0
  each_item do |profile, host|
    result = passwd_rekey(["--rekey", profile, host], verbose, true)
    next if result == 2
    status = 1 if result != 0
    $stderr.puts "granular-passwd: rekeyed #{profile} #{host}" if result == 0
  end
  status
end

# granular-passwd --export <profile> <host>: writes the username and the token as two lines, for a pipe
# into --stdin or into git credential-osxkeychain. It will not write to a terminal.
def passwd_export(args, verbose)
  profile = args[1]
  host = args[2]
  if G.isatty(1) != 0
    $stderr.puts "granular-passwd: --export writes to a pipe, not a terminal"
    return 1
  end
  return 1 unless passwd_ready(verbose)
  words = G.granular_kc_login(KEYCHAIN_PREFIX + profile + ":" + host, "").split(" ")
  if words.length < 2
    $stderr.puts "granular-passwd: no #{profile} item for #{host}"
    return 1
  end
  puts words[0]
  puts words[1]
  0
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
args = ARGV
# granular <applet> ...: the same as running through the link of that name.
if name == "granular" && args.length > 0 && APPLETS.include?(args[0])
  name = args[0] == "gh" ? "gh" : SELF_PREFIX + args[0]
  args = args[1..-1]
end
exit gh_wrapper(args) if name == "gh"
verbose = false
if args[0] == "-v"
  verbose = true
  args = args[1..-1]
end
program = name.start_with?(SELF_PREFIX) ? name[SELF_PREFIX.length..-1] : ""
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
if args.length == 1 && args[0] == "--version"
  puts VERSION
  exit 0
end
if args.length == 1 && (args[0] == "-h" || args[0] == "--help") && program != "git"
  USAGE.each { |l| puts l }
  exit 0
end
if program == "git" && args.length == 1
  exit git_helper(args[0])
elsif program == "passwd" && args.length == 2 && args[0] == "--rekey" && args[1] == "--all"
  exit passwd_rekey_all(verbose)
elsif program == "passwd" && args.length == 3 && args[0] == "--export"
  exit passwd_export(args, verbose)
elsif program == "passwd" && (args.length == 3 || args.length == 4) && args[0] == "--rekey"
  exit passwd_rekey(args, verbose, false)
elsif program == "passwd" && (args.length == 3 || args.length == 4) && args[0] == "--stdin"
  exit passwd_store(args[1..-1], verbose, true)
elsif program == "passwd" && (args.length == 2 || args.length == 3)
  exit passwd_store(args, verbose, false)
elsif program == "daemon" && args.length == 0
  exit daemon(verbose)
elsif program == "trust" && args.length == 0
  exit trust_chain
end
USAGE.each { |l| $stderr.puts l }
exit 2
