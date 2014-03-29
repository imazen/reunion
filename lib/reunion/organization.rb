module Reunion

  class OrganizationCache
    attr_accessor :org_creator
    def initialize(&org_creator)
      @org_creator = org_creator
    end

    def org_computed
      @org_computed ||= org_parsed(deep_copy:true).ensure_computed! 
    end

    def org_parsed(deep_copy: true)
      load_parsed! unless @org_parsed_dump
      unless @org_parsed_dump
        parsed = org_creator.call()
        parsed.ensure_parsed!
        @org_parsed_dump = Marshal.dump(parsed)
        @org_parsed = parsed
        File.open(parsed_cache_path, 'w'){|f| f.write(@org_parsed_dump)}
      end 
      deep_copy ? Marshal.restore(@org_parsed_dump) : @org_parsed
    end  

    #for troubleshooting
    def find_proc(obj, chain = "", maxdepth=100)
      return if maxdepth < 0
      return unless obj
      chain = chain + "(#{obj.class})"
      puts "\n\nFound proc at #{chain}\n\n" if obj.is_a?(Proc)
      obj.instance_variables.each do |name|
        find_proc(obj.instance_variable_get(name), "#{chain}>#{name}", maxdepth-1)
      end
      if obj.is_a? Array
        obj.each_with_index do |v, ix|
          find_proc(v, "#{chain}>[#{ix}]", maxdepth-1)
        end
      end
      if obj.is_a? Hash
        obj.each do |k, v|
          find_proc(k, "#{chain}>[#{k.inspect}]",maxdepth-1)
          find_proc(v, "#{chain}>[#{k.inspect}]",maxdepth-1)
        end
      end
    end

    def invalidate_parsing!
      invalidate_computations!
      @org_parsed = nil
      @org_parsed_dump = nil
      File.delete(parsed_cache_path) if File.exist?(parsed_cache_path)
    end 
    
    def invalidate_computations!
      @org_computed = nil
    end

    def load_parsed!
      @org_parsed_dump = File.read(parsed_cache_path) if File.exist?(parsed_cache_path)
      if @org_parsed_dump
        #begin
          @org_parsed = Marshal.restore(@org_parsed_dump) 
          @org_parsed.log << "Loaded from disk (parsed_data) at #{DateTime.now}"
        #rescue => e
        #  puts "Failed to restore dump from disk"
        #  puts e
        #  @org_parsed_dump = nil
        #end
      end
    end  

    def cache_folder
      unless @cache_folder
        temp = org_creator.call()
        temp.configure
        @cache_folder = temp.root_dir
      end 
      @cache_folder
    end 

    def parsed_cache_path
      File.join(cache_folder, "parsed_data.bin")
    end

 
  end 

  class Organization

    #schema

  
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