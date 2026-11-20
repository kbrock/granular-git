require_relative "helper"

describe Remote do
  let(:remote) { Remote.new("/tmp/sock") }

  it "says down when there is no daemon" do
    G.double.expect(:granular_fetch_socket, -1, ["/tmp/sock"])
    assert_equal "down", remote.ask("get x")
  end

  it "denies a socket that is not private" do
    G.double.expect(:granular_fetch_socket, -2, ["/tmp/sock"])
    assert_equal "deny socket is not private to you", remote.ask("get x")
  end

  it "writes the line, reads the reply and closes" do
    G.double.expect(:granular_fetch_socket, 7, ["/tmp/sock"])
    G.double.expect(:granular_write_line, 0, [7, "get x"])
    G.double.expect(:granular_read_line, "ok a b", [7])
    G.double.expect(:granular_close, 0, [7])
    assert_equal "ok a b", remote.ask("get x")
    G.double.verify
  end

  it "asks for a token with the host and user" do
    G.double.expect(:granular_fetch_socket, -1, ["/tmp/sock"])
    assert_equal "down", remote.token("github.com", "me")
  end
end
