module Reunion
  class Organization

    #schema

  
    attr_reader :bank_accounts, :root_dir

    def configure
    end

    def locate_input
    end 

    def load_and_merge
      bank_accounts.each do |a|
        a.load_and_merge
        a.reconcile
      end
      @all_transactions = bank_accounts.map{|a| a.transactions}.flatten.stable_sort_by{|t| t.date_str}
    end 
    attr_reader :all_transactions,  :overrides_path

    
    def ensure_loaded
      return if defined? @loaded
      configure
      locate_input
      load_and_merge
      @loaded = true
    end   

    def ensure_complete
      return if defined? @complete
      ensure_loaded
      apply_rules_and_overrides
      @complete = true
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
        r = Rules.new
        r.instance_eval(contents, full_path)
        
        {full_path: full_path, 
            contents: contents,
            rules: r, 
            engine: RuleEngine.new(r)}.merge(d)
      end
    end


    def apply_rules_and_overrides
      @overrides = OverrideSet.load(overrides_path)
      @overrides.apply_all(all_transactions)
      @rule_sets = create_rule_sets
      @rule_sets.each do |r|
        r[:engine].run(all_transactions)
      end
      @overrides.apply_all(all_transactions)
      @transfer_pairs, transfers = get_transfer_pairs(all_transactions.select{|t| t[:transfer]}, all_transactions)
      @unmatched_transfers = transfers.select{|t| t[:transfer_pair].nil?}

    end

    attr_reader :rule_sets

    attr_reader :transfer_pairs, :unmatched_transfers

  
  end
end 