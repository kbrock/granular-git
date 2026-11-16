# The keychain file that holds the logins.
class Vault
  def initialize(path)
    @path = path
  end

  # The item name for a profile's login on a host: "granular:<profile>:<host>".
  def item(profile, host)
    KEYCHAIN_PREFIX + profile + ":" + host
  end

  # "<user> <token> <description words>" for the item, or "". The token is the Keychain's to give: a read can
  # wait on a prompt.
  def login(item, user)
    G.granular_kc_login(item, user)
  end

  # 0 if the item is stored.
  def set(item, user, token, description)
    G.granular_kc_set(item, user, token, description)
  end

  # Points the Keychain calls at the vault. 0 if it is open, -1 if the file is missing.
  def open
    G.granular_vault(@path)
  end

  # Opens the vault, creating it first if the file is missing. False if it cannot.
  def ensure
    return true if open == 0
    warn "granular-passwd: creating #{@path}. A dialog asks for its password."
    if G.granular_vault_create(@path) != 0 || open != 0
      warn "granular-passwd: cannot create #{@path}"
      return false
    end
    true
  end

  # Yields the profile and host of each item in the vault.
  def each_item
    n = G.granular_kc_list_open(KEYCHAIN_PREFIX)
    n.times do |i|
      name = G.granular_kc_list_get(i)
      next if name == ""
      rest = name[KEYCHAIN_PREFIX.length..]
      colon = rest.index(":")
      yield rest[0, colon], rest[colon + 1..] if colon
    end
    G.granular_kc_list_close
  end

  # Reads a secret from the terminal without echo.
  def read_secret(prompt)
    G.granular_read_secret(prompt)
  end
end
