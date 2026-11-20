require_relative "helper"

describe Vault do
  let(:vault) { Vault.new("/tmp/v.keychain-db") }

  it "names an item by profile and host" do
    assert_equal "granular:ro:github.com", vault.item("ro", "github.com")
  end

  it "opens the vault file" do
    G.double.expect(:granular_vault, 0, ["/tmp/v.keychain-db"])
    assert_equal 0, vault.open
  end

  it "does not create a vault that opens" do
    G.double.expect(:granular_vault, 0, ["/tmp/v.keychain-db"])
    assert vault.ensure
    G.double.verify
  end

  it "yields the profile and host of each item" do
    G.double.expect(:granular_kc_list_open, 3, ["granular:"])
    G.double.expect(:granular_kc_list_get, "granular:ro:github.com", [0])
    G.double.expect(:granular_kc_list_get, "", [1])
    G.double.expect(:granular_kc_list_get, "granular:rw:gitlab.com", [2])
    G.double.expect(:granular_kc_list_close, 0)
    seen = []
    vault.each_item { |profile, host| seen << [profile, host] }
    assert_equal [["ro", "github.com"], ["rw", "gitlab.com"]], seen
  end
end
