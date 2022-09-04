module Reunion

  class Organization

    attr_reader :bank_accounts, :root_dir, :overrides_path, :schema, :syntax, :overrides_results, :truncate_before
    attr_reader :all_transactions, :remove_processor_prefixes

    

    attr_reader :rule_sets, :overrides

    attr_reader :transfer_pairs, :unmatched_transfers

    @profile = false

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

    def enable_profiling!
      @profile = true
      require 'ruby-prof'
      #require 'ruby-prof-flamegraph'
    end 

    def drop_transactions_before(date)
      @truncate_before = date
    end 

    def warn_about_unused_input
      no_account_files = all_input_files.select{|f| f.account.nil? }
      log << "Failed to match the following files to accounts:\n" + no_account_files.map{|f| f.path} * "\n" if no_account_files.length > 0

      no_parser_files = all_input_files.select{|f| f.parser.nil? }
      log << "Failed to match the following files to parsers (they were therefore not added to their accounts either):\n" + no_parser_files.map{|f| f.path} * "\n" if no_parser_files.length > 0

    end
    def parse!
      Benchmark.bm(label_width = 55) do |benchmark|
        times = []
        #ractors = []
        bank_accounts.each do |a|
          times << benchmark.report("Loading and merging files for account #{a.name}") do
            if !truncate_before.nil? && (a.truncate_before.nil? || (!a.truncate_before.nil? && a.truncate_before < truncate_before)) then 
              a.drop_transactions_before(truncate_before)
            end
            a.load_and_merge(schema: schema, remove_processor_prefixes: remove_processor_prefixes)
          end
          times << benchmark.report("Reconciling account #{a.name} against balances") do
            a.reconcile
          end
          
          
          times <<benchmark.report("Writing #{a.permanent_id.to_s}.txt and .reconcile.txt") do
            basepath = File.join(bank_accounts_output_dir, a.permanent_id.to_s)
            FileUtils.mkdir_p(bank_accounts_output_dir) unless Dir.exist?(bank_accounts_output_dir)
            File.open("#{basepath}.txt", 'w'){|f| f.write(a.normalized_transactions_report)}
            File.open("#{basepath}.reconcile.txt", 'w'){|f| f.write(Export.new.pretty_reconcile_tsv(a.reconciliation_report))}
          end
        end
        times << benchmark.report('Combining & sorting all transactions') do
          @all_transactions = bank_accounts.map{|a| a.transactions}.flatten.stable_sort_by{|t| t.date_str}
          
        end
        [times.inject(Benchmark::Tms.new(), :+)]
      end
      #result =  "Executed parse and sort of transactions in #{time}"
      #log << result
      #STDERR << result
      #profiling_result("parse", RubyProf.stop) if @profile
    end 
  
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
      computable_transactions = @all_transactions.reject { |t| t[:skip_compute] }
      raise "computed transactions nil!" if computable_transactions.nil?

      Benchmark.bm(label_width = 55) do |benchmark|
        benchmark.report("#{all_transactions.length} transactions (#{computable_transactions&.length} computable) present") {}
        benchmark.report('Load and apply overrides') do
          @overrides = OverrideSet.load(overrides_path, schema)
          @overrides.apply_all(all_transactions)
        end
        benchmark.report("Create rule sets") do
          @rule_sets = create_rule_sets
        end
        @rule_sets.each do |r|
          benchmark.report("Execute ruleset #{r[:full_path][-20..-1]}") do
            r[:engine].run(computable_transactions)
          end 
        end
        benchmark.report('Apply overrides again)') do
          @overrides_results = @overrides.apply_all(all_transactions)
        end
        benchmark.report('Log override misses)') do
          @overrides_results[:unused_overrides].each do |ov|
            log << "Override unused: #{ov.lookup_key_basis} -> #{ov.changes_json}\n"
          end
        end
        transfer_txns = computable_transactions.select { |t| t[:transfer] }
        benchmark.report("Pair #{transfer_txns.length} bank transfers and card payoffs") do
#         File.open("transfers.txt", 'w') { |f| f.write(Export.new.input_file_to_tsv(transfer_txns)) }
          @transfer_pairs, transfers = get_transfer_pairs(transfer_txns, computable_transactions)
          @unmatched_transfers = transfers.select { |t| t[:transfer_pair].nil? }
        end
        benchmark.report("#{ @unmatched_transfers.length} unmatched transfers remain") {}
      end
    end

    def profiling_result(name, result)
      STDERR << "Processing profiling result..."
      printer = RubyProf::GraphPrinter.new(result)
      printer.print(STDERR, :min_percent=>1)
      printer = RubyProf::MultiPrinter.new(result)
      printer.print(:path => ".", :profile => name, :printers => [:graph, :flat, :graph_html, :stack, :tree, :call_info, :dot])
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
      ensure_computed!
      time = Benchmark.measure{
        exp = ReportExporter.new
        datasource = ReportDataSource.new(all_transactions,all_transactions, schema)
        report_list ||= reports
        report_list.each do |r|
          result = {}
          report_time = Benchmark.measure{
            result = ReportGenerator.new.generate(slugs: [r.slug], reports: report_list, datasource: datasource)
          }
          message = "Generated #{r.title} in #{report_time}.  Exporting..."
          write_time = Benchmark.measure{
            exp.export(result, File.join(root_dir, "output/reports"))
          }
          message += " exported in #{write_time}\n"
          STDERR.puts(message)
        end
      }
      message = "Exported in #{time}"
      log << message
      STDERR << message
    end

  
  end
end 