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
        #files = org.all_input_files
        #require 'pry'
        #binding.pry
        slim :'import/sources', {layout: :layout, :locals => {:files => org.all_input_files}}
      end 
      
      get '/import/sources/:digest' do |digest|
        slim :'import/details', {layout: :layout, :locals => {:file => org.all_input_files.detect{|f| f.path_account_digest == digest}}}
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
            sort_urls[f] = "/reports/#{r.path}?sort_by=#{f}&sort_asc=#{sort_asc}"
          else
            sort_urls[f] = "/reports/#{r.path}?sort_by=#{f}&sort_asc=false"
          end 
        end

        
        if params["format"] == "csv"
          STDERR << "making csv...\n"
          attachment filename
          content_type "text/csv"
          body = ReportExporter.new.export_csv(report: r, schema: org.schema, 
            txn_fields: fields
          )
          content_length body.bytesize
          body
        else
          slim :report, {:layout => :layout, :locals => {:r => r, sort_urls: sort_urls, :basepath => '/reports/'}}
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

      get '/repl' do
        slim :'repl', {:layout => :layout, :locals => {:schema =>org.schema, syntax: org.syntax}}
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
