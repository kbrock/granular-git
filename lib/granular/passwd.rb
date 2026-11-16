# granular-passwd: stores, rekeys and exports the logins in the vault.
class Passwd
  def initialize(can:, vault:, caller_profile:, stdout_tty:, verbose:)
    @vault = vault
    @can = can
    @caller_profile = caller_profile
    @stdout_tty = stdout_tty
    @verbose = verbose
  end

  # <profile> <host> [description]: asks for a username and a token.
  def store(profile:, host:, description:, from_stdin:)
    return 1 unless ready?
    $stderr.print "Username: " unless from_stdin
    user = ($stdin.gets || "").chomp
    if user == "" || user.include?(" ")
      warn "granular-passwd: username must be non-empty with no spaces"
      return 1
    end
    token = from_stdin ? ($stdin.gets || "").chomp : @vault.read_secret("Token: ")
    if token == ""
      warn "granular-passwd: no token read"
      return 1
    end
    write(@vault.item(profile, host), user, token, description)
  end

  # --rekey <profile> <host> [description]: stores the item again with its own user and
  # token, so its access list names this build. Without a description the old one is kept.
  def rekey(profile:, host:, description: "", set_description: false, quiet: false)
    return 1 unless ready?
    item = @vault.item(profile, host)
    words = @vault.login(item, "").split(" ")
    if words.length < 2
      warn "granular-passwd: no #{profile} item for #{host}" unless quiet
      return quiet ? 2 : 1
    end
    kept = (words.length > 2) ? words[2..].join(" ") : ""
    write(item, words[0], words[1], set_description ? description : kept)
  end

  # --rekey --all: rekeys every item that exists, one prompt each, so they come together.
  def rekey_all
    return 1 unless ready?
    status = 0
    @vault.each_item do |profile, host|
      result = rekey(profile: profile, host: host, quiet: true)
      next if result == 2
      status = 1 if result != 0
      warn "granular-passwd: rekeyed #{profile} #{host}" if result == 0
    end
    status
  end

  # --export <profile> <host>: writes the username and the token as two lines, for a pipe
  # into --stdin or into git credential-osxkeychain. It will not write to a terminal.
  def export(profile:, host:)
    if @stdout_tty
      warn "granular-passwd: --export writes to a pipe, not a terminal"
      return 1
    end
    return 1 unless ready?
    words = @vault.login(@vault.item(profile, host), "").split(" ")
    if words.length < 2
      warn "granular-passwd: no #{profile} item for #{host}"
      return 1
    end
    puts words[0]
    puts words[1]
    0
  end

  # Checks shared by every form: the caller may run passwd, the vault is there.
  def ready?
    unless @can.allow?(profile: @caller_profile, command: "passwd")
      warn "granular-passwd: refusing to run under Claude or an unknown caller"
      return false
    end
    @vault.ensure
  end

  # Stores the item and reads it back.
  def write(item, user, token, description)
    if @vault.set(item, user, token, description) != 0
      warn "granular-passwd: keychain write failed"
      return 1
    end
    if @vault.login(item, user) != user + " " + token + ((description == "") ? "" : " " + description)
      warn "granular-passwd: stored value did not read back"
      return 1
    end
    warn "granular-passwd: stored and verified #{token.length} bytes for #{item} / #{user}" if @verbose
    0
  end
end
