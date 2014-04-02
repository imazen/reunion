module Reunion

  class Organization

    attr_reader :bank_accounts, :root_dir, :overrides_path, :schema, :syntax

    def log
      @log ||= []
    end


    def configure
      @schema = TransactionSchema.new
      @syntax = StandardRuleSyntax.new(@schema)
    end

    def locate_input
    end 

    def parse!
      bank_accounts.each do |a|
        a.load_and_merge(schema)
        a.reconcile
      end
      @all_transactions = bank_accounts.map{|a| a.transactions}.flatten.stable_sort_by{|t| t.date_str}
    end 
    attr_reader :all_transactions 

    
    def ensure_parsed!
      return if defined? @loaded
      configure
      locate_input
      parse!
      @loaded = true
      self
    end   

    def ensure_computed!
      return if defined? @complete
      ensure_parsed!
      define_syntax
      compute!
      @complete = true
      self
    end 

    def define_syntax
      @syntax = StandardRuleSyntax.new(@schema)
    end

    def rule_set_descriptors
      #[{
       # path: "input/rules/vendors.rb",
       # name: "Vendors",
       # run_count: 1}
      []
    end

    def create_rule_sets
      rule_set_descriptors.map do |d|
        full_path = File.join(root_dir, d[:path])
        contents = File.read(full_path)
        r = Rules.new(syntax)
        r.instance_eval(contents, full_path)
        
        {full_path: full_path, 
            contents: contents,
            rules: r, 
            engine: RuleEngine.new(r)}.merge(d)
      end
    end


    def compute!
      
      #RubyProf.start
      time = Benchmark.measure{
        @overrides = OverrideSet.load(overrides_path)
        @overrides.apply_all(all_transactions)
        @rule_sets = create_rule_sets
        @rule_sets.each do |r|
          r[:engine].run(all_transactions)
        end
        @overrides.apply_all(all_transactions)
        @transfer_pairs, transfers = get_transfer_pairs(all_transactions.select{|t| t[:transfer]}, all_transactions)
        @unmatched_transfers = transfers.select{|t| t[:transfer_pair].nil?}
      }
      result =  "Executed rules, transfer detection, and overrides in #{time}"
      log << result
      #result = RubyProf.stop
      #printer = RubyProf::FlatPrinter.new(result)
      #printer.print(STDERR)
      #require pry
      #binding.pry
    end

    attr_reader :rule_sets, :overrides

    attr_reader :transfer_pairs, :unmatched_transfers

  
  end
end 