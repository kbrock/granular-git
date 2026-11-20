require "minitest/autorun"
require "minitest/mock"

# G is the C shim in the real build. Under plain Ruby it sends each call to G.double, which a test sets to a
# mock (or to a World).
module G
  class << self
    attr_accessor :double

    def method_missing(name, *args)
      double.public_send(name, *args)
    end

    def respond_to_missing?(name, include_private = false)
      true
    end
  end
end

# A small process tree for the walk: pid, parent, executable path and working directory. A process that was
# removed has no start time, as an exited process does.
class World
  attr_accessor :claudes, :me

  def initialize
    @procs = {}
    @claudes = ""
    @me = 0
  end

  # launchd > login > bash > claude > git
  def self.standard
    new.add(1, 0, "/sbin/launchd")
      .add(100, 1, "/usr/bin/login")
      .add(101, 100, "/bin/bash", cwd: ENV["HOME"] + "/src/app")
      .add(102, 101, "/opt/homebrew/bin/claude")
      .add(103, 102, "/usr/bin/git")
  end

  def add(pid, parent, path, cwd: "/")
    @procs[pid] = {parent: parent, path: path, cwd: cwd}
    self
  end

  def remove(pid)
    @procs.delete(pid)
  end

  def getpid
    @me
  end

  def granular_parent_pid(pid)
    @procs.key?(pid) ? @procs[pid][:parent] : -1
  end

  def granular_pid_path(pid)
    @procs.key?(pid) ? @procs[pid][:path] : ""
  end

  def granular_pid_exec(pid)
    granular_pid_path(pid)
  end

  def granular_pid_start(pid)
    @procs.key?(pid) ? "1.#{pid}" : ""
  end

  def granular_pid_cwd(pid)
    @procs.key?(pid) ? @procs[pid][:cwd] : ""
  end

  def granular_claude_pids
    @claudes
  end
end

lib = File.expand_path("../../lib/granular", __dir__)
%w[config node vault chain wire can table terminal remote responder local fallback trust daemon cli].each { |f| require "#{lib}/#{f}" }

# Each test starts with a fresh mock for G unless it sets a World.
module Minitest
  class Spec
    before { G.double = Minitest::Mock.new }
  end
end
