# Everything the programs are made of. granular.rb and dev/granular.rb load it.
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

require_relative "granular/config"
require_relative "granular/node"
require_relative "granular/vault"
require_relative "granular/chain"
require_relative "granular/wire"
require_relative "granular/can"
require_relative "granular/table"
require_relative "granular/terminal"
require_relative "granular/remote"
require_relative "granular/responder"
require_relative "granular/local"
require_relative "granular/fallback"
require_relative "granular/git"
require_relative "granular/daemon"
require_relative "granular/gh"
require_relative "granular/trust"
require_relative "granular/passwd"
require_relative "granular/cli"
