module Reunion

  class Organization

    attr_reader :bank_accounts, :root_dir, :overrides_path, :schema, :syntax, :overrides_results

    def log
      @log ||= []
    end

    def bank_accounts_output_dir
      File.join(root_dir, "output/accounts")
    end 

    def configure
      @schema = TransactionSchema.new
      @syntax = StandardRuleSyntax.new(@schema)
    end

    def locate_input
    end 

    def warn_about_unused_input
      no_account_files = all_input_files.select{|f| f.account.nil? }
      log << "Failed to match the following files to accounts:\n" + no_account_files.map{|f| f.path} * "\n" if no_account_files.length > 0

      no_parser_files = all_input_files.select{|f| f.parser.nil? }
      log << "Failed to match the following files to parsers (they were therefore not added to their accounts either):\n" + no_parser_files.map{|f| f.path} * "\n" if no_parser_files.length > 0

    end 
    def parse!
      bank_accounts.each do |a|
        a.load_and_merge(schema)
        a.reconcile

        Dir.mkdir(bank_accounts_output_dir) unless Dir.exist?(bank_accounts_output_dir)
        basepath = File.join(bank_accounts_output_dir, a.permanent_id.to_s)
        File.open("#{basepath}.txt", 'w'){|f| f.write(a.normalized_transactions_report)}
        File.open("#{basepath}.reconcile.txt", 'w'){|f| f.write(Export.new.pretty_reconcile_tsv(a.reconciliation_report))}
      end
      @all_transactions = bank_accounts.map{|a| a.transactions}.flatten.stable_sort_by{|t| t.date_str}
    end 
    attr_reader :all_transactions 

    
    def ensure_parsed!
      return if defined? @loaded
      configure
      locate_input
      warn_about_unused_input
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
        @overrides = OverrideSet.load(overrides_path, schema)
        @overrides.apply_all(all_transactions)
        @rule_sets = create_rule_sets
        @rule_sets.each do |r|
          r[:engine].run(all_transactions)
        end
        @overrides_results = @overrides.apply_all(all_transactions)
        @overrides_results[:unused_overrides].each do |ov|
          log << "Override unused: #{ov.lookup_key_basis} -> #{ov.changes_json}\n"
        end
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

    def reports
      []
    end

    def generate_report(slugs, **options)
      gen = ReportGenerator.new
      txns = all_transactions
      report = gen.generate(slugs: slugs, reports: reports, datasource: ReportDataSource.new(txns,txns, schema), **options)
      report 
    end

    def export_reports!(report_list = nil)
      exp = ReportExporter.new
      datasource = ReportDataSource.new(all_transactions,all_transactions, schema)
      report_list ||= reports
      report_list.each do |r|
        result = ReportGenerator.new.generate([r.slug], report_list, datasource)
        exp.export(result, File.join(root_dir, "output/reports"))
      end
    end


    attr_reader :rule_sets, :overrides

    attr_reader :transfer_pairs, :unmatched_transfers

  
  end
end 