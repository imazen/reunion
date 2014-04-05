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
      end
      @changes = changes 
    end 

    attr_accessor :account_str, :date_str, :amount_str, :description, :subindex, :changes, :schema

    def lookup_key_basis
      [account_str,date_str,amount_str,description.strip.squeeze(" ").downcase,subindex.to_s] * "|"
    end 

    def lookup_digest
      @lookup_digest ||= Digest::SHA1.hexdigest(lookup_key_basis)
    end 

    def changes_json
      fmt = Hash[changes.to_a.map do |pair| 
        pair[1].nil? ? pair : [pair[0],schema.format_field(pair[0], pair[1])]
      end]
      JSON.generate(changes)
    end 

    def load_changes_from_json(str)
      obj = JSON.parse(str)
      raise "Don't know how to load anything except a hash #{obj.inspect}" unless obj.is_a?(Hash)
      obj = Hash[obj.map do |k,v| 
        key = k.to_sym
        value = schema[key] ? schema[key].normalize(v) : v.to_sym
        [key,value]
      end]
      @changes = obj
    end 


    def ==(o)
      o.class == self.class && o.state == state
    end
    alias_method :eql?, :==

    protected

    def state
      [@account_str, @date_str, @amount_str, @description,@subindex,@changes]
    end
  end

  class OverrideSet

    attr_accessor :overrides, :by_info, :filename, :schema

    def initialize(schema)
      @overrides ||= {}
      @schema = schema
    end

    def to_tsv_str
      e = Export.new
      cols = [{name: "Account"},{name: "Date"},{name:"Amount"},{name:"Description"},{name:"Subindex"},{name:"Changes"}]
      rows = overrides.values.map{|ov| {account: ov.account_str, date: ov.date_str, amount: ov.amount_str, description: ov.description, subindex: ov.subindex.to_s, changes: ov.changes_json}}

      rows.sort_by!{|r| [r[:date],r[:account], r[:description], r[:amount], r[:subindex]] }
      e.pretty_tsv(cols, rows)
    end

    def self.load(filename, schema)
      if File.exist? filename
        contents = File.read(filename)
        set = from_tsv_str(contents, schema)
      else
        set = OverrideSet.new(schema)
      end 
      set.filename = filename

      set
    end 

    def save(path = nil)
      path ||= filename
      File.write(path, to_tsv_str)
    end 

    def self.from_tsv_str(contents, schema)
      a = StrictTsv.new(contents.encode('UTF-8').rstrip).parse

      set = OverrideSet.new(schema)

      by_primary = []

      a.each do |r|
        ov = Override.new
        ov.schema = schema
        ov.account_str = r[:account].strip.downcase
        ov.date_str = Date.parse(r[:date]).strftime("%Y-%m-%d")
        ov.amount_str = "%.2f" % BigDecimal.new(r[:amount].gsub(/[\$,]/, ""))
        ov.description = r[:description].gsub(/\s+/," ").strip
        ov.subindex = Integer(r[:subindex].strip)
        ov.load_changes_from_json(r[:changes])
        by_primary << [ov.lookup_digest, ov]
      end
      set.overrides = Hash[by_primary]
      set
    end

    def by_txn(txn)
      overrides[txn.lookup_key]
    end 

    def set_override(txn,changes)
      old = by_txn(txn)
      ov = Override.new(txn,changes)
      ov.changes = {}.merge(old.changes).merge(ov.changes) if old && old.changes
      ov.schema = schema
      overrides[ov.lookup_digest] = ov
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
