# The dev build: the same programs with every command open, and the vault named by GRANULAR_VAULT. Built to
# build/dev/ and run only by bin/ci-dev. Nothing in the release build requires this directory.
require_relative "../lib/granular"
require_relative "open_can"

cli = Cli.new
cli.can = OpenCan.new
cli.vault = Vault.new(ENV["GRANULAR_VAULT"])
exit cli.run(File.basename($0), ARGV)
