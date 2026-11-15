# The keychain file that holds the logins.
class Vault
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
