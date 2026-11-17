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
  ffi_func :granular_accept, [:int], :int
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

require_relative "lib/granular/config"
require_relative "lib/granular/node"
require_relative "lib/granular/vault"
require_relative "lib/granular/chain"
require_relative "lib/granular/wire"
require_relative "lib/granular/can"
require_relative "lib/granular/table"
require_relative "lib/granular/terminal"
require_relative "lib/granular/remote"
require_relative "lib/granular/responder"
require_relative "lib/granular/local"
require_relative "lib/granular/fallback"
require_relative "lib/granular/git"
require_relative "lib/granular/daemon"
require_relative "lib/granular/gh"
require_relative "lib/granular/trust"
require_relative "lib/granular/passwd"
require_relative "lib/granular/cli"

exit Cli.new.run(File.basename($0), ARGV)
