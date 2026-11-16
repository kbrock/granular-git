# The keychain file that holds the logins.
class Vault
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
    G.granular_vault(ENV["HOME"] + "/Library/Keychains/" + VAULT)
  end

  # Opens the vault, creating it first if the file is missing. False if it cannot.
  def ensure
    return true if open == 0
    path = ENV["HOME"] + "/Library/Keychains/" + VAULT
    warn "granular-passwd: creating #{path}. A dialog asks for its password."
    if G.granular_vault_create(path) != 0 || open != 0
      warn "granular-passwd: cannot create #{path}"
      return false
    end
    true
  end
end
