require "sinatra/base"
require "slim"
require "json"
require "rouge"

module Rack
  class CommonLogger
    def call(env)
      # do nothing
      @app.call(env)
    end
  end
end

module Reunion
  module Web
    class App < ::Sinatra::Base

      set :dump_errors, true

      set :show_exceptions, false




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
        def get_date_from
          @@date_from ||= Date.parse('2013-01-01')
        end

        def get_date_to
          @@date_to ||= Date.parse('2014-01-01')
        end

        def org
          org_cache.org_computed
        end

      end 

      def filter_transactions(txns, drop_paired_transfers = true)
        txns.select do |t| 
          keep = true
          keep = false if t[:transfer_pair] && drop_paired_transfers
          #keep =  false if get_date_from && t.date < get_date_from
          #keep =  false if get_date_to && t.date > get_date_to
          keep
        end 
      end 

      def get_transfer_pairs
        org.transfer_pairs
      end

      post '/set_date_from/:from' do |from|
        @@date_from = from
      end 

      post '/set_date_to/:to' do |to|
        @@date_to = to
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
        slim :'import/details', {layout: :layout, :locals => {:file => org.all_input_files.select{|f| f.path_account_digest == digest}.first}}
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
        redirect to('/import/sources')
      end 

      get '/search' do
        slim :search, {layout: :layout, :locals => {:query => ""}}
      end
 
      post '/overrides/:id' do |id|
        content_type :json
        key = params[:key].downcase.to_sym
        field = org.schema.fields[key]
        value = field.normalize(params[:value])

        txn = org.all_transactions.select{|t| t.lookup_key == id}.first

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

      set :dump_errors, true

      set :show_exceptions, false

      get '/expense/:year/:query/?' do |year, query|
        list = org.all_transactions.map{|t| t[:tax_expense]}.uniq
        years = org.all_transactions.map{|t| t.date.year}.uniq
        query = query.to_s.downcase.to_sym


        results = filter_transactions(org.all_transactions).select{|t| query == :none ? t[:tax_expense].to_s.empty? : t[:tax_expense] == query}
        results = results.select{|t| t.date.year == year.to_i} if year.to_i > 1900

        slim :expense, {:layout => :layout, :locals => {:results => results, :query => query, :tax_expense_names => list, :years => years, :year => year}}
      end

      get '/reports/?' do
        list = org.reports.map{|r| {name: r.title, path: "/reports/#{r.slug}"}}
        slim :report_list,  {:layout => :layout, :locals => {:reports => list}}
      end 

      get %r{^\/reports/?(.+)$} do |slugs|
        slugs = slugs.split('/').compact.reject{|s| s.empty?}
        STDERR << "Locating report " + slugs.join('/')  + "\n"

        simplified = (params["simple"] == "true")

        r = org.generate_report(slugs, simplified_totals: simplified)

        if params["format"] == "csv"
          STDERR << "making csv...\n"
          attachment "#{slugs.join('_')}.csv"
          content_type "text/csv"
          ReportExporter.new.export_csv(report: r, schema: org.schema, 
            txn_fields: [:date, :amount,:currency, :description, :vendor, :subledger, :memo, :description2, :account_sym, :id]
          )
        else
          slim :report, {:layout => :layout, :locals => {:r => r, :basepath => '/reports/'}}
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
