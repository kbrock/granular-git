require_relative "lib/granular"

exit Cli.new.run(File.basename($0), ARGV)
