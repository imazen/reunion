module Reunion

  #todo - how do we handle the transaction ID? Or should we ignore it? What about currency?

  class Override
    def initialize(txn = nil, changes = {})
      if txn
        OverrideSet.assert_has_subindex(txn)
        @account_str = txn.account_sym.to_s
        @date_str = txn.date_str
        @amount_str = "%.2f" %  txn.amount
        @description = txn.description
        @subindex = txn[:subindex]
        @txn_id = txn[:id]
      end
      @changes = changes 
    end 

    attr_accessor :account_str, :date_str, :amount_str, :description, :subindex, :changes, :txn_id 

    def lookup_key
      account_str + "|" + date_str + "|" + amount_str + "|" + description.strip.squeeze(" ").downcase + "|" + subindex.to_s
    end 

    def lookup_digest
      Digest::SHA1.hexdigest(lookup_key)
    end 

    def changes_json
      JSON.generate(changes)
    end 

    def load_changes_from_json(str)
      obj = JSON.parse(str)
      @changes = symbolfy(obj)
    end 

    def symbolfy(obj)
      if obj.is_a? Array
        obj.map{|v|symbolfy(v)}
      elsif obj.is_a? Hash
        Hash[obj.to_a.map{ |pair| [symbolfy(pair[0]), symbolfy(pair[1])]}]
      elsif obj.is_a? String 
        obj.strip.downcase.to_sym
      else
        raise "Don't know how to symbolfy #{obj.inspect}"
      end 
    end 

    def ==(o)
      o.class == self.class && o.state == state
    end
    alias_method :eql?, :==

    protected

    def state
      [@account_str, @date_str, @amount_str, @description,@subindex,@changes,@txn_id]
    end



  end

  class OverrideSet

    def initialize
      @overrides ||= {}
    end

    def to_tsv_str
      e = Export.new
      e.pretty_tsv([{name: "Account"},{name:"Id"},{name: "Date"},{name:"Amount"},{name:"Description"},{name:"Subindex"},{name:"Changes"}],
       overrides.values.map{|ov| {id: ov.txn_id, account: ov.account_str, date: ov.date_str, amount: ov.amount_str, description: ov.description, subindex: ov.subindex.to_s, changes: ov.changes_json}})
    end

    def self.from_tsv_str(contents)
      a = StrictTsv.new(contents.encode('UTF-8').rstrip).parse

      set = OverrideSet.new

      pairs = a.map do |r|
        ov = Override.new
        ov.account_str = r[:account].strip.downcase
        ov.txn_id = r[:id].strip.downcase
        ov.txn_id = nil if ov.txn_id.empty?
        ov.date_str = Date.parse(r[:date]).strftime("%Y-%m-%d")
        ov.amount_str = "%.2f" % BigDecimal.new(r[:amount].gsub(/[\$,]/, ""))
        ov.description = r[:description].gsub(/\s+/," ").strip
        ov.subindex = Integer(r[:subindex].strip)
        ov.load_changes_from_json(r[:changes])
        [ov.lookup_key, ov]
      end

      set.overrides = Hash[pairs]
      set
    end

    def by_txn(txn)
      overrides[get_txn_key(txn)]
    end 
    def set_changes(txn, changes)
      key = get_txn_key(txn)
      overrides[key] ||= Override.new(txn,changes)
    end 

    def self.assert_has_subindex(transaction)
      raise "Transaction without subindex found. Call set_subindexes on ALL transactions before using the Overrides system" if transaction[:subindex].nil?
    end

    def get_txn_key(t)
      OverrideSet.assert_has_subindex(t)
      t.account_sym.to_s + "|" + t.date_str + "|" + ("%.2f" %  t.amount) + "|" + t.description.strip.squeeze(" ").downcase + "|" + t[:subindex].to_s
    end


    attr_accessor :overrides

    def set_subindexes(absolutely_all_transactions)
      txns = absolutely_all_transactions
      #Group into identical transactions
      match = lambda { |t|  t.account_sym.to_s + "|" + t.date_str + "|" + ("%.2f" %  t.amount) + "|" + t.description.strip.squeeze(" ").downcase  }
      groups = txns.stable_sort_by{ |t| match.call(t)}.chunk(&match).map{|t| t[1]}
      groups.each do |g| 
        g.each_with_index do |txn, ix| 
          txn[:subindex] = ix
        end
      end
    end 



    def apply_all(transactions)
      transactions.each do |t|
        result = overrides[get_txn_key(t)]
        if result
          result.changes.each_pair do |k,v|
            t[k] = v
          end
        end
      end
    end

  end
end
