require "sinatra/base"
require "slim"
require "json"
require "commonmarker"
require "better_errors"

module Rack
  class CommonLogger
    def call(env)
      # do nothing
      @app.call(env)
    end
  end
end

BetterErrors.ignored_classes = ['Reunion::Transaction', 'Reunion::Statement']

module Reunion
  module Web
    class App < ::Sinatra::Base

      def initialize(org_creator:)
        super
        create_org = org_creator
        
      end

      set :dump_errors, true

      set :show_exceptions, true

      disable :reload_templates

      attr_accessor :create_org

      configure :development do
        use BetterErrors::Middleware
        BetterErrors.application_root = __dir__
        
      end
      
      def self.root_dir
        File.dirname(__FILE__)
      end 

      def self.views_dir
        File.join(File.dirname(__FILE__), 'views')
      end 

      puts "App reloaded"

      set :root, File.dirname(__FILE__)

      attr_accessor :org_cache

      helpers do
        def org_cache
          $org ||= Reunion::OrganizationCache.new(&create_org)
        end 
        def org
          org_cache.org_computed
        end

        def parsed_ago
          Reunion::TimeAgo.ago_in_words(org_cache.org_computed.parsed_at)
        end 
        def computed_ago
          Reunion::TimeAgo.ago_in_words(org_cache.org_computed.computed_at)
        end 
      end 
     
  
      def org_cache
        $org ||= Reunion::OrganizationCache.new(&create_org)
      end 

      def org
        org_cache.org_computed
      end

      def filter_transactions(txns, drop_paired_transfers = true)
        txns.select do |t| 
          keep = true
          keep = false if t[:transfer_pair] && drop_paired_transfers
          keep
        end 
      end 

      def get_transfer_pairs
        org.transfer_pairs
      end


      post '/reparse' do
        org_cache.invalidate_parsing!
        redirect request.referer
      end

      post '/recompute' do
        org_cache.invalidate_computations!
        redirect request.referer
      end

      post '/export' do
        org.export_reports!
        redirect request.referer
      end

      get '/debug' do
        slim :'debug', {layout: :layout, :locals => {:stats => GC.stat}}
      end 

      get '/import/sources' do
        slim :'import/sources', {layout: :layout, :locals => {:files => org.all_input_files}}
      end 
      
      get '/import/sources/:digest' do |digest|
        slim :'import/details', {layout: :layout, :locals => {:all_txns => org.all_transactions,:file => org.all_input_files.detect{|f| f.path_account_digest == digest}}}
      end 

      get '/import/validate' do
        validation_errors = org.all_transactions.map{|t| {txn: t, errors: t[:schema].validate(t)} }.select{|r| !r[:errors].nil?}
        slim :'import/validate', {layout: :layout, :locals => {:errors => validation_errors, :org => org}}
      end 

      get '/bank' do
        slim :'bank/index', {layout: :layout, :locals => {:bank_accounts => org.bank_accounts}}
      end

      get '/bank/:id/reconcile' do |id|
        slim :'bank/reconcile', {layout: :layout, :locals => {:bank => org.bank_accounts.find{|a|a.permanent_id == id.to_sym}}}
      end



      get '/transfers' do
        slim :unmatched_transfers, {layout: :layout, :locals => {:query => ""}}
      end

      get '/transfers/unmatched' do
        results = filter_transactions(org.unmatched_transfers)
        slim :unmatched_transfers, {:layout => :layout, :locals => {:results => results}}
      end

      get '/transfers/paired' do
        results = org.transfer_pairs
        slim :transfer_pairs, {:layout => :layout, :locals => {:results => results}}
      end


      get '/' do

        readme_html = org.readme_markdown ? 
            Tilt['markdown'].new(context: self) { org.readme_markdown }.render :
            "No README.md file found"

        config_report = org.config_report_hash || {}
        slim :readme, {:layout => :layout, :locals => {:readme_html => readme_html,
          :config_report => config_report }}
      end 

      get '/search' do
        slim :search, {layout: :layout, :locals => {:query => ""}}
      end
 
      post '/overrides/:id' do |id|
        content_type :json
        key = params[:key].downcase.to_sym
        field = org.schema.fields[key]
        value = field.normalize(params[:value])

        txn = org.all_transactions.detect{|t| t.lookup_key == id}

        existing_override = org.overrides.by_txn(txn) 

        changes = existing_override.nil? ? {} : existing_override.changes
        
        oldval = changes[key] || txn[key]
        if oldval != value
          changes[key] = value
          org.overrides.set_override(txn,changes)
          change_made = true
        end 
        if change_made
          org.overrides.save 
          org.overrides.apply_all(org.all_transactions)
        end
        {change_made: change_made, normalized_value: value, id: id, key: key, warnings: field.validate(value)}.to_json
      end

      get '/search/:query' do |query|
        results = filter_transactions(org.all_transactions).select{|t| t.description.downcase.include?(query.downcase)}

        slim :search, {:layout => :layout, :locals => {:results => results, :query => query}}
      end


      get '/expense/:year/:query/?' do |year, query|
        list = org.all_transactions.map{|t| t[:tax_expense]}.uniq
        years = org.all_transactions.map{|t| t.date.year}.uniq
        query = query.to_s.downcase.to_sym


        results = filter_transactions(org.all_transactions).select{|t| query == :none ? t[:tax_expense].to_s.empty? : t[:tax_expense] == query}
        results = results.select{|t| t.date.year == year.to_i} if year.to_i > 1900

        slim :expense, {:layout => :layout, :locals => {:results => results, :query => query, :tax_expense_names => list, :years => years, :year => year}}
      end

      get '/reports/?' do
        # last year based on now
        last_year = Date.today.year - 1
        list = org.reports.map{|r| {name: r.title, path: "/reports/#{r.slug}", last_year: last_year, last_year_path: "/reports/#{r.slug}/#{last_year}"}}
        slim :report_list,  {:layout => :layout, :locals => {:reports => list}}
      end 

      get %r{\/reports/?(.+)} do |slugs|
        slugs = slugs.split('/').compact.reject{|s| s.empty?}
        STDERR << "Locating report " + slugs.join('/')  + "\n"

        simplified = (params["simple"] == "true")
        begin 
          r = org.generate_report(slugs, simplified_totals: simplified)
        rescue Exception => e
          if e.to_s.include?("Failed to find report")
            $stderr << "Report missing... redirecting to parent report\n"
            #$stderr << e.to_s
            redirect "/reports/#{slugs[0..-2] * '/'}"
          else
            raise
          end 
        end 

        current_base_url = "/reports/#{r.path}"
        #filter out 'captures' key
        current_url_params = params.dup.reject{|k,v| k == "captures"}
   
        field_set = (params["field_set"] || "default").to_sym

        fields = case field_set
          when :default 
            [:date, :amount,:currency, :description, :vendor, :subledger, :memo, :description2, :account_sym, :id]
          when :tax
            [:tax_expense, :date, :amount,  :description, :currency]
          when :exex
            [:date, :amount,:currency, :description, :vendor, :vendor_tags, :subledger, :memo, :tax_expense, :description2, :account_sym, :id]
        end 
        
        filename = case field_set
          when :default
            "#{slugs.join('_')}.csv"
          when :tax
            "Transactions-#{slugs.join('_')}.csv"
          when :exex
            "ExEx-expensecsv-#{slugs.join('_')}.csv"  
        end 

        sort_by = params["sort_by"]
        sort_asc = params["sort_asc"] == "true"
        sort_urls = {}

        search_description = params["search_desc"]

        original_count = r.transactions.nil? ? 0 : r.transactions.count

        if !search_description.nil? && !search_description.empty? && r.transactions
          r.transactions = r.transactions.select{|t| t.description.downcase.include?(search_description.downcase)}
        end

        r.schema.fields.keys.each do |f|
          if sort_by && f.to_sym == sort_by.to_sym
          
            r.transactions.sort! do |a, b|
              if a[f].nil?
                1
              elsif b[f].nil?
                -1
              else
                a[f] <=> b[f]
              end
            end
            r.transactions.reverse! if !sort_asc
            sort_asc = !sort_asc

            # deep copy params, set sort_asc and sort_by and encode and append to current_base_url
            new_params = params.dup.merge({sort_by: f, sort_asc: sort_asc})
          else
            new_params = params.dup.merge({sort_by: f, sort_asc: false})
          end 
          sort_urls[f] = "#{current_base_url}?#{URI.encode_www_form(new_params)}"
        end


        transaction_metadata = nil
        if r.transactions
          transaction_metadata = r.transactions.map do |txn|
            metadata = {}
            if txn[:amount] && r.schema.fields[:amount] && txn[:date]
              
              #search within 2 weeks of charge
              #Create a link from txn[:date] and txn[:amount] in the form https://mail.google.com/mail/u/0/#advanced-search/subset=all&has=%2210.00%22&within=2w&date=2023%2F08%2F30
              # build the query as a hash then url encode
              # trim - and $ from amount
              amount_str = r.schema.fields[:amount].format(txn[:amount]).gsub(/[-$]/,'')
              query = { subset: "all", has: "\"#{amount_str}\"", within: "2w", date: txn[:date].strftime("%Y/%m/%d") }
              # url encode and & delimit query hash
              query_str = URI.encode_www_form(query)
              # build the url
              metadata[:search_url] = "https://mail.google.com/mail/u/0/#advanced-search/#{query_str}" 
            end 
            # search by the first word of the description, 
            if txn[:description]
              first_word = txn[:description].split(' ').first
              new_params = params.dup.merge({search_desc: first_word})
              metadata[:filter_url] =  "#{current_base_url}?#{URI.encode_www_form(new_params)}" 
            end
            metadata
          end
        end

        # describe current_url_params and offer a link to the base url
        current_filter_explanation = if current_url_params.empty?
          nil
        else
          string = ""
          unless search_description.nil? || search_description.empty? || r.transactions.nil?
            net_amount = r.transactions.map{|t| t.amount}.sum

            string += "(description contains '#{search_description}' - showing #{r.transactions.count} of #{original_count}. Net amount: #{r.schema.fields[:amount].format(net_amount)} "  
          end
          if sort_by
            string += "sorting #{sort_asc ? 'ascending' : 'descending'} by #{sort_by}."
          end 
          string + ")"
        end

        
        if params["format"] == "csv"
          STDERR << "making csv...\n"
          attachment filename
          content_type "text/csv"
          body = ReportExporter.new.export_csv(report: r, schema: org.schema, 
            txn_fields: fields
          )
          # content_length body.bytesize
          body
        else
          slim :report, {:layout => :layout, :locals => {:r => r, :transaction_metadata => transaction_metadata, sort_urls: sort_urls, :basepath => '/reports/', unfiltered_url: current_base_url, current_filter_explanation: current_filter_explanation}}
        end
      end

      get '/expense/?:year?/?' do |year| 

        year ||= "allyears"

        txns = filter_transactions(org.all_transactions)
        all_txns = filter_transactions(org.all_transactions, false)
        
        txns = txns.select{|t| t.date.year == year.to_i} if year.to_i > 1900
        all_txns = all_txns.select{|t| t.date.year == year.to_i} if year.to_i > 1900

        list = org.all_transactions.map{|t| t[:tax_expense]}.uniq
        years = org.all_transactions.map{|t| t.date.year}.uniq
        slim :expense, {layout: :layout, :locals => {:query => "", :tax_expense_names => list, :txns => txns, :all_txns => all_txns, :years => years, :year => year}}
      end


      get '/rules' do
        rules = org.rule_sets
        slim :rules, {:layout => :layout, :locals => {:groups => rules, :ruleset => nil, :code => nil, 
          codehtml: nil, codecss: nil, syntax: org.syntax}}
      end 

      get '/rules/:setname' do |setname|
        
        require "rouge"
        rules = org.rule_sets

        set = rules.find{|r| r[:name].downcase == setname}

        reporter = RulesReporter.new(set[:engine])
        code = reporter.interpolate(set[:contents], File.basename(set[:path]))

        codehtml = Rouge::Formatters::HTML.new(:css_class => 'highlight').format(Rouge::Lexers::Ruby.new.lex(code))

        codecss = Rouge::Themes::Base16.render(:scope => '.highlight')


        slim :rules, {layout: :layout, locals: {groups: rules, ruleset: set, 
          code: code, codehtml: codehtml, codecss:codecss, syntax: org.syntax}}
      end 

      get '/repl/:query' do |query|
        slim :'repl', {:layout => :layout, :locals => {:schema =>org.schema, query: query, syntax: org.syntax}}
      end 

      get '/repl' do
        slim :'repl', {:layout => :layout, :locals => {:schema =>org.schema, query: "", syntax: org.syntax}}
      end 

      post '/repl' do
        content_type :json
        code = params[:ruby]
        r = Rules.new(org.syntax)

        begin
          r.eval_string(code)
        rescue Exception => e
          return {errors:e}.to_json
        end

        rs = RuleEngine.new(r)

        matches = rs.find_matches(org.all_transactions).flatten
        cleaned = matches.map{|t| {lookup_key: t.lookup_key}.merge(Hash[t.data.map{|k,v| [k,t.schema.format_field(k,v)]}])}
        #STDERR << "Found #{matches.count} results within #{org.all_transactions.count} for \n#{code}\n #{rs.rules.inspect}\n\n #{cleaned.inspect}"
        {results: cleaned}.to_json
      end


      get '/transaction/:id' do |id|
        results = org.all_transactions.select{|t| t.lookup_key == id}
        slim :'transaction/details', {:layout => :layout, :locals => {:results => results, :txn => results.first, :key => id}}
      end 

    end
  end
end
