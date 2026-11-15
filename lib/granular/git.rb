# granular-git: the git credential helper.
class Git
  def initialize(source)
    @source = source
  end

  def run(action:)
    # $stderr.puts "granular-git: store ignored" if action == "store"
    return 0 unless action == "get"

    host = ""
    user = ""
    while (line = $stdin.gets)
      line = line.chomp
      break if line == ""
      host = line[5..] if line.start_with?("host=")
      user = line[9..] if line.start_with?("username=")
    end
    return 0 if host == ""

    reply = @source.token(host, user)
    if reply.start_with?("deny no item ")
      warn "granular: no token for #{host} profile #{reply[13..]}"
      return 0
    end
    login = login_parts(reply)
    if login.length != 3
      warn "granular-git: #{(reply == "") ? "no reply from daemon" : reply}"
      return 1
    end
    warn "granular: " + login[2] unless login[2] == ""
    puts "username=#{login[0]}"
    puts "password=#{login[1]}"
    0
  end
end
