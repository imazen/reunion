module Reunion

  class Organization

    attr_reader :bank_accounts, :root_dir, :overrides_path, :schema, :syntax, :overrides_results, :truncate_before
    attr_reader :all_transactions, :remove_processor_prefixes, :remove_processor_prefixes_after, :parsed_at, :computed_at


    def self.precompute_for_web!(org_creator:, reparse: false, recompute: false)
      $stderr << "Loading books...\n"
      $stderr << "Reparsing...\n" if reparse
      $stderr << "Recomputing...\n" if reparse || recompute

      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      cache_init_started = t0

      # Initialize or reuse cache
      $org ||= Reunion::OrganizationCache.new(&org_creator)
      cache_init_done = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      $org.invalidate_parsing! if reparse
      $org.invalidate_computations! if recompute && !reparse

      ensure_started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      if ENV['STACKPROF'] == '1'
        require 'stackprof'
        StackProf.run(mode: :cpu, out: ENV['STACKPROF_OUT'] || 'tmp/stackprof-boot.dump', interval: (ENV['STACKPROF_INTERVAL'] || '1000').to_i) do
          $org.org_computed.ensure_computed! #Easier to have it start work while we're opening our browser
        end
      else
        $org.org_computed.ensure_computed!
      end

      ensure_done = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      $stderr << "To speed up: export RUBY_GC_HEAP_INIT_SLOTS=#{(GC.stat[:heap_live_slots]*1.5).to_i}\n"

      total = ensure_done - t0
      cache_init = cache_init_done - cache_init_started
      ensure_time = ensure_done - ensure_started
      $stderr << format("Boot timings: total=%.3fs, cache_init=%.3fs, ensure_computed=%.3fs (gc_live=%d)\n",
                        total, cache_init, ensure_time, GC.stat[:heap_live_slots])

      $stderr << "Books loaded\n"
     
      #$stderr << GC.stat
    end 

    def bank_file_tags
      @bank_file_tags ||= {}
      bank_accounts.each do |a|
        a.file_tags.each do |tag|
          @bank_file_tags[tag.downcase.to_sym] = a
        end
      end
      @bank_file_tags
    end 


    def web_app_title
      self.class.name.split('::').last.sub('Org', '') || 'Reunion'
    end

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

    def readme_markdown
      "Add a readme.md file - and this to your Org subclass:<br/>" + 
      "<code>def readme_html\n  @@readme ||= File.read(File.expand_path('readme.md', File.dirname(__FILE__)))\nend"
    end 

    def config_report_hash
      configure
      {
#TODO
      }
    end 

    def inspect 
      "<Reunion::Organization (truncated for your sanity)>"
    end 

    def get_relevant_files
      locate_input.map{ |f| f.path } + rule_set_descriptors.map{ |h| h[:path]} + @code_paths
    end 

    def input_files_hash
      sha256 = Digest::SHA256.new
      get_relevant_files.each do |path|
        sha256 << File.read(path)
      end 
      sha256.hexdigest
    end

    def needs_reparse
      return "no @inputs_hash" unless @inputs_hash
      @inputs_hash != input_files_hash ? "hash mismatch" : nil
    end  

    def txn_count
      all_transactions.length
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
            a.load_and_merge(schema: schema, remove_processor_prefixes: remove_processor_prefixes,
              remove_processor_prefixes_after: remove_processor_prefixes_after, transaction_modifier: respond_to?(:modify_transactions) ? method(:modify_transactions) : nil)
          end
          times << benchmark.report("Reconciling account #{a.name} against balances") do
            a.reconcile
          end
          
          
          times << benchmark.report("Writing #{a.permanent_id.to_s}.txt and .reconcile.txt") do
            basepath = File.join(bank_accounts_output_dir, a.permanent_id.to_s)
            FileUtils.mkdir_p(bank_accounts_output_dir) unless Dir.exist?(bank_accounts_output_dir)
            File.open("#{basepath}.txt", 'w'){|f| f.write(a.normalized_transactions_report)}
            File.open("#{basepath}.reconcile.txt", 'w'){|f| f.write(Export.new.pretty_reconcile_tsv(a.reconciliation_report))}
          end
        end
        times << benchmark.report('Combining & sorting all transactions') do
          @all_transactions = bank_accounts.map{|a| a.transactions}.flatten.stable_sort_by{|t| t.date_str}
          
        end
        @parsed_at = Time.now
        [times.inject(Benchmark::Tms.new(), :+)]
      end
      @inputs_hash = input_files_hash
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
          @overrides_results_first = @overrides.apply_all(all_transactions, ignore_unused_before_date: truncate_before, ignore_unused_after_date: truncate_before)
        end
        benchmark.report('Log override misses') do
          @overrides_results_first[:unused_overrides].each do |ov|
            log << "Override unused: #{ov.lookup_key_basis} -> #{ov.changes_json}\n"
          end
        end
        benchmark.report("Create rule sets") do
          @rule_sets = create_rule_sets
        end
        @rule_sets.each do |r|
          benchmark.report("Execute ruleset #{r[:full_path][-20..-1]}") do
            r[:engine].run(computable_transactions)
          end 
        end
        # benchmark.report('Apply overrides again)') do
        #   @overrides_results = @overrides.apply_all(all_transactions)
        # end
        # benchmark.report('Log override misses)') do
        #   @overrides_results[:unused_overrides].each do |ov|
        #     log << "Override unused: #{ov.lookup_key_basis} -> #{ov.changes_json}\n"
        #   end
        # end
        transfer_txns = computable_transactions.select { |t| t[:transfer] }
        benchmark.report("Pair #{transfer_txns.length} bank transfers and card payoffs") do
#         File.open("transfers.txt", 'w') { |f| f.write(Export.new.input_file_to_tsv(transfer_txns)) }
          @transfer_pairs, transfers = get_transfer_pairs(transfer_txns, computable_transactions)
          @unmatched_transfers = transfers.select { |t| t[:transfer_pair].nil? }
        end
        benchmark.report("#{ @unmatched_transfers.length} unmatched transfers remain") {}
      end
      @computed_at = Time.now
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

    def export_report_set!(
      reports: nil,
      to_folder: nil, 
      filenames_to_slug_array: nil, 
      txn_fields: [:date, :amount,  :description, :tax_expense, :currency])
      
      $stdout << "\nComputing accounts..\n"
      ensure_computed!

      to_folder = File.expand_path(to_folder || "./output/exports", @root_dir)

      reports = reports || filenames_to_slug_array.map { |k,v| {filename: k, report_slugs: v}}
    
      reports.each do |report|
        name = report[:filename]
        slug_array = report[:report_slugs]
        
        target_file =  File.expand_path(name, to_folder)
        target_file = "#{target_file}.csv" unless target_file.end_with?('.csv')

        FileUtils.mkdir_p(File.dirname(target_file)) unless Dir.exist?(File.dirname(target_file))

        $stdout << "\nGenerating data for #{slug_array * '/'}\n"

        begin 
          r = generate_report(slug_array)
          csv_contents = Reunion::ReportExporter.new.export_csv(report: r, 
              schema: schema, 
              txn_fields: report[:txn_fields] || txn_fields)
          $stdout << "\nWriting #{r.transactions&.length} transactions from #{slug_array * '/'} to #{target_file}\n"
          File.open(target_file, 'w') { |f| f.write(csv_contents) }
        rescue Exception => e
          unless e.to_s.include?('Failed to find report')
            raise
          else
            $stderr << "Failed to find report (no transactions): #{e}\n"
          end 
        end 
      end 

      $stdout << "\nExport complete\n"
    end
  end
end 