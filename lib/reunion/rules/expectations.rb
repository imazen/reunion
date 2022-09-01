module Reunion
  class Expectations

    def initialize
      @stack = []
      @entities = {}
      @searcher = nil
    end

    def [](key)
      key = key.is_a?(Symbol) ? key : key.to_s.downcase.to_sym
      @entities[key] ||= {}
      @entities[key]
    end 

    def eval(to_push, &block)
      @stack << to_push
      r = self.instance_eval(&block)
      add_hash(r) if r.is_a?(Hash)
      @stack.pop
      nil
    end

    def mention(commentary, &block)
      eval({commentary: commentary}, &block)
    end 

    def with_focus(tag, &block)
      eval({focus: tag}, &block)
    end

    def invalidate_searcher
      @searcher = nil
    end 

    def get_searcher
      @searcher ||= EntitySearcher.new(@entities)
    end

    def add_hash(pairs)
      pairs.each do |k,v|
        add_entity k,v
      end 
    end 

    def add_entity(name, value)
      invalidate_searcher
      v = self[name] 
      v[:queries] ||= []
      query = nil
      if value.is_a?(Hash)
        v[:description] ||= value[:description] || value[:desc] || value[:d]
        v[:focus] ||= value[:focus] || value[:f] || @stack.map{|s| s[:focus]}.compact.last
        v[:commentary] ||= @stack.map{|s| s[:commentary]}.compact.last
        query = value[:queries] || value[:query] || value[:q]
      else
        query = value
      end

      if query.is_a?(Array)
        query.each{|q| add_entity(name,q)} 
      elsif query.is_a?(Regexp) || (query.is_a?(String) && query.length > 1)
        v[:queries] << query 
      elsif !query.nil?
        raise "Unknown query type #{query.inspect}"
      end 
    end

    def set_focus(name, value)
      self[name][:focus] = value
    end 
    def add(pairs =nil, &block)
      add_hash(pairs) unless pairs.nil?
      if block
        add_hash(block.call)
      end
      nil
    end

    def suggest_vendors(transactions)
      #Show common descriptions without an associated vendor?

      groups_by_desc = transactions.select{|t| t.vendor.nil? && !t.description.nil?}.
      stable_sort_by{|t| t.description.downcase}.chunk{|t|t.description.downcase}.map{|t| t[1]}.sort_by{|t| t.length}.reverse

      puts "These vendors have been suggested for you, most frequently used first"
      puts "add do\n  {"
      groups_by_desc.each do |g|
        #Only check for repeat transactions with a total negative amount
        next if g.length < 2 || g.map{|t| t[:amount]}.compact.inject(0, :+) > 0.1
        d = g.last.description
        v = d.downcase.gsub(/\d\d\d+/,"").gsub("'","").gsub(/ inc| llc|\.com/,"")
        v = v.gsub(/[^a-z0-0 ]/," ").squeeze(" ").strip.gsub(/\A[0-9]+/,"").gsub(" ", "_")
        puts "#{v}: \"#{g.last.description}\",     #(#{g.length}x)\n"
      end
      puts "}"
    end

    def suggest(transactions)
      #After each stage, exclude transactions already matched by expecations




      #Show vendors, then descriptions, with a single monthly charge (exclude credits maybe?)
      #Show vendors, then descriptions, with a single yearly charge

      #Show vendors with avg interval < 40 and max interval < 80. Establish monthly budget.

      #Show vendors with avg interval < 100 days and establish yearly budget


      #suggest_by(transactions, :amount_vendor){ |t| t.vendor.nil? ? nil : (t.vendor.to_s  + ("|%.2f" %  t.amount))}
      
      #suggest_by(transactions, :amount_description){ |t| ("%.2f" %  t.amount) + "|" + t.description.downcase}
      #suggest_by(transactions, :description){ |t| t.description.downcase}
      suggest_by(transactions, :vendor){ |t| t[:vendor]}
    end



    def suggest_by(transactions, field, &block)
      
      sorted = transactions.reject{|t| block.call(t).nil?}.stable_sort_by{ |t| block.call(t) }
      #Array of arrays
      grouped = sorted.chunk(&block).map{|t| t[1]}

      grouped.each do |set|
        analyze_set set, transactions, field, block
      end 
    end 

    def analyze_set(similar_transactions, all_transactions, field, block)
      return if similar_transactions.length < 2

      last_import_date = all_transactions.map{|t| t[:date]}.compact.sort.last

      set = similar_transactions
      dates = set.map{|t| t[:date]}.compact.sort

      intervals = dates.each_with_index.map { |d,ix| ix > 0 ? (d.mjd - dates[ix - 1].mjd) : nil}.compact
      raise "Intervals empty " if intervals.empty?
      interval_avg = intervals.inject(:+).to_f / intervals.size
      #interval_deltas = intervals.map{|i| (interval_avg - i).abs}
      #interval_deltas_avg = interval_deltas.inject(:+).to_f / interval_deltas.size
      #interval_deltas.avg
      #first_date = dates.first

      return if interval_avg < 20 || interval_avg > 40 ||
      has_last_date = (last_import_date.mjd - (interval_avg * 2)) > dates.last.mjd

      msg = ""
      msg << "#{set.length}x " + block.call(set.first).to_s
      msg << " every #{intervals.min.floor} to #{intervals.max.ceil} (~#{interval_avg.round}) days from"
      msg << " #{dates.first.strftime('%Y-%m-%d')} until " + (has_last_date ? "#{dates.last.strftime('%Y-%m-%d')}" : "now")
      msg << "\n"
      msg << ("%.2f" %  set.first.amount) + "    " + set.first.description 
      puts msg
      puts "\n\n"

      #What was the first date? -> dates.first
      #Did they stop prior to the normal interval?

      #Focus
      #---regular interval single transaction
      #---monthly averages


      #----
      #What is the average interval
      #What is the average deviation from that interval
      #What is the average yearly spend
      #What is the average monthly spend



    end 


  end
end 