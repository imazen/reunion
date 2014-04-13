module Reunion

  class RulesReporter

    def initialize(engine)
      @rules = engine.rules
    end


    def by_line_number(filename)
      Hash[@rules.map do |r|
        trace = r.chain.last[:stacktrace].map{ |x|   
          x.match(/^(.+?):(\d+)(|:in `(.+)')$/); 
          [$1,$2,$4]
        }

        line_number = trace.find{|a| a[0].downcase.end_with?(filename.downcase)}[1]

        matched_count = r.matched_transactions.uniq.count
        [line_number.to_i,matched_count]
      end]
    end

    def interpolate(text, filename)
      line_matches = by_line_number(filename)
      STDERR << line_matches.inspect
      new_text = ""
      text.lines.each_with_index do |line, ix|
        new_text << line.rstrip 
        count = line_matches[ix + 1]
        new_text << "\t\# matched: #{count}" if count
        new_text << "\n"
      end
      new_text
    end
  end

end
