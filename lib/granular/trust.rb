# granular-trust: this process and its parents, one per line, outermost first and without launchd. The
# number is the distance up from this process: 0 is this process, -1 its parent.
class Trust
  def initialize(chain)
    @chain = chain
  end

  def run
    chain = @chain.ancestors(G.getpid)
    j = chain.length - 1
    while j >= 0
      if chain[j] > 1
        puts "#{(j == 0) ? "0" : "-" + j.to_s}  #{@chain.name(chain[j])}  #{chain[j]}"
      end
      j -= 1
    end
    0
  end
end
