module Reunion

  class RulesReporter

    def initialize(engine)
      @rules = engine.rules
    end


    def by_line_number(filename)
      by_lines = {}
      @rules.each do |r|
        trace = r.chain.last[:stacktrace].map{ |x|   
          x.match(/^(.+?):(\d+)(|:in `(.+)')$/); 
          [$1,$2,$4]
        }

        line_number = trace.find{|a| a[0].downcase.end_with?(filename.downcase)}[1]

        matched_count = r.matched_transactions.uniq.count
        by_lines[line_number.to_i] ||= []
        by_lines[line_number.to_i] << {count: matched_count, rule: r}
      end
      by_lines
    end

    def interpolate(text, filename)
      line_matches = by_line_number(filename)
      new_text = ""
      text.lines.each_with_index do |line, ix|
        rules = line_matches[ix + 1]
        if rules
          counts = rules.map{|r|r[:count]}
          message = "matched: #{counts.join ', '}"
          if counts.inject(0, :+) == 0
            #If there were no matches, let's do a diagnostic
            message = rules.map{|r|
              r.inspect
            }.join(",")
          end
          message = "\t\# #{message}" 
        end 
        new_text << "#{line.rstrip}#{message}\n"
      end
      new_text
    end
  end

end
