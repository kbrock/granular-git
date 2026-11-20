# The dev build's Can: every profile may run every command, so a test can set its own profile.
class OpenCan < Can
  def allow?(profile:, command:, args: [])
    true
  end
end
