module Reunion

  #todo - how do we handle the transaction ID? Or should we ignore it? What about currency?

  class Override
    def initialize(txn = nil, changes = {})
      if txn
        txn.lookup_key
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

    def lookup_key_basis
      [account_str,date_str,amount_str,description.strip.squeeze(" ").downcase,subindex.to_s] * "|"
    end 

    def lookup_digest
      @lookup_digest ||= Digest::SHA1.hexdigest(lookup_key_basis)
    end 

    def txn_id_digest
      @txn_id_digest ||= txn_id.to_s.empty? ? nil : Digest::SHA1.hexdigest(txn_id)
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
      elsif obj.nil?
        nil
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

    attr_accessor :overrides, :by_info, :filename

    def initialize()
      @overrides ||= {}
      @by_info ||= {}
    end

    def to_tsv_str
      e = Export.new
      e.pretty_tsv([{name: "Account"},{name:"Id"},{name: "Date"},{name:"Amount"},{name:"Description"},{name:"Subindex"},{name:"Changes"}],
       overrides.values.map{|ov| {id: ov.txn_id, account: ov.account_str, date: ov.date_str, amount: ov.amount_str, description: ov.description, subindex: ov.subindex.to_s, changes: ov.changes_json}})
    end

    def self.load(filename)
      if File.exist? filename
        contents = File.read(filename)
        set = from_tsv_str(contents)
      else
        set = OverrideSet.new
      end 
      set.filename = filename

      set
    end 

    def save(path = nil)
      path ||= filename
      File.write(path, to_tsv_str)
    end 

    def self.from_tsv_str(contents)
      a = StrictTsv.new(contents.encode('UTF-8').rstrip).parse

      set = OverrideSet.new

      by_primary = []
      by_info = []

      a.each do |r|
        ov = Override.new
        ov.account_str = r[:account].strip.downcase
        ov.txn_id = r[:id].strip.downcase
        ov.txn_id = nil if ov.txn_id.empty?
        ov.date_str = Date.parse(r[:date]).strftime("%Y-%m-%d")
        ov.amount_str = "%.2f" % BigDecimal.new(r[:amount].gsub(/[\$,]/, ""))
        ov.description = r[:description].gsub(/\s+/," ").strip
        ov.subindex = Integer(r[:subindex].strip)
        ov.load_changes_from_json(r[:changes])
        by_primary << [ov.txn_id_digest || ov.lookup_digest, ov]
        by_info << [ov.lookup_digest, ov.txn_id_digest] unless ov.txn_id_digest.nil?
      end
      set.overrides = Hash[by_primary]
      set.by_info = Hash[by_info]
      set
    end

    def by_txn(txn)
      by_digest(txn.lookup_key)
    end 

    def by_digest(digest)
      overrides[digest] || overrides[by_info[digest]]
    end 

    def set_override(txn,changes)
      ov = Override.new(txn,changes)
      overrides[ov.txn_id_digest || ov.lookup_digest] = ov 
      by_info[ov.lookup_digest] = ov.txn_id_digest unless ov.txn_id_digest.nil?
    end 

    def self.set_subindexes(absolutely_all_transactions)
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
        result = by_txn(t)
        if result
          result.changes.each_pair do |k,v|
            t[k] = v
          end
        end
      end
    end

  end
end
