require "sinatra"
require "slim"
require "json"

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

      puts "App reloaded"

      set :root, File.dirname(__FILE__)

      attr_accessor :org

      helpers do
        def get_date_from
          @@date_from ||= Date.parse('2013-01-01')
        end

        def get_date_to
          @@date_to ||= Date.parse('2014-01-01')
        end

      end 

      before do
        org.ensure_complete
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
        get_cached_books.transfer_pairs
      end

      post '/set_date_from/:from' do |from|
        @@date_from = from
      end 

      post '/set_date_to/:to' do |to|
        @@date_to = to
      end 

      def get_books
        org
      end


      def get_cached_books
        @@books ||= get_books
      end

      get '/import/sources' do
        slim :'import/sources', {layout: :layout, :locals => {:files => org.all_input_files}}
      end 
      
      get '/import/sources/:digest' do |digest|
        slim :'import/details', {layout: :layout, :locals => {:file => org.all_input_files.select{|f| f.path_account_digest == digest}.first}}
      end 

      get '/import/validate' do
        validation_errors = org.all_transactions.map{|t| {txn: t, errors: t[:schema].validate(t)} }.select{|r| !r[:errors].nil?}
        slim :'import/validate', {layout: :layout, :locals => {:errors => validation_errors}}
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
        results = filter_transactions(get_cached_books.unmatched_transfers)
        slim :unmatched_transfers, {:layout => :layout, :locals => {:results => results}}
      end

      get '/transfers/paired' do
        results = get_cached_books.transfer_pairs
        slim :transfer_pairs, {:layout => :layout, :locals => {:results => results}}
      end


      get '/' do
        redirect to('/expense')
      end 

      get '/search' do
        slim :search, {layout: :layout, :locals => {:query => ""}}
      end

      def txns_to_workon
        get_cached_books.all_transactions.select do |t|
          keep = true
          keep = false if t[:transfer_pair]
          keep = false if t.date < Date.parse('2013-03-16')
          keep = false if t.date > Date.parse('2014-03-19')
          keep = false if [:income, :owner_draw].include?(t[:tax_expense])
          keep = false if t[:rebill] == :no
          keep
        end
      end 

      get '/overrides' do
        slim :'overrides/index', {layout: :layout, :locals => {:results => txns_to_workon}}
      end

      post '/overrides' do
        change_made = false
        params.each_pair do |k,v|
          unless v.to_s.empty? || !k.start_with?('memo_')
            digest = k.sub /\Amemo_/, ""
            txn = get_cached_books.all_transactions.select{|t| t.lookup_key == digest}.first
            existing = get_cached_books.overrides.by_digest(digest)
            changes = existing.nil? ? {} : existing.changes
            oldval = changes[:memo] || txn[:memo]
            if oldval != v
              changes[:memo] = v
              get_cached_books.overrides.set_override(txn,changes)
              change_made = true
            end 
          end 
        end 
        if change_made
          get_cached_books.overrides.save 
          get_cached_books.overrides.apply_all(get_cached_books.all_transactions)
        end

        slim :'overrides/index', {layout: :layout, :locals => {:results => txns_to_workon}}
      end 

      post '/overrides/:id' do |id|
        content_type :json
        key = params[:key].downcase.to_sym
        field = org.schema.fields[key]
        value = field.normalize(params[:value])

        txn = org.all_transactions.select{|t| t.lookup_key == id}.first

        existing_override = org.overrides.by_digest(id) 

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
        results = filter_transactions(get_cached_books.all_transactions).select{|t| t.description.downcase.include?(query.downcase)}

        slim :search, {:layout => :layout, :locals => {:results => results, :query => query}}
      end

      get '/expense/?' do

        txns = filter_transactions(get_cached_books.all_transactions)
        all_txns = filter_transactions(get_cached_books.all_transactions, false)
        list = get_cached_books.all_transactions.map{|t| t[:tax_expense]}.uniq
        slim :expense, {layout: :layout, :locals => {:query => "", :tax_expense_names => list, :txns => txns, :all_txns => all_txns}}
      end

      set :dump_errors, true

      set :show_exceptions, false

      get '/expense/:query' do |query|
        list = get_cached_books.all_transactions.map{|t| t[:tax_expense]}.uniq
        query = query.to_s.downcase.to_sym


        results = filter_transactions(get_cached_books.all_transactions).select{|t| query == :none ? t[:tax_expense].to_s.empty? : t[:tax_expense] == query}

        slim :expense, {:layout => :layout, :locals => {:results => results, :query => query, :tax_expense_names => list}}
      end

      get '/rules' do
        rules = get_cached_books.rule_sets
        slim :rules, {:layout => :layout, :locals => {:rules => rules}}
      end 

      get '/rules/repl' do
        slim :'rules/repl', {:layout => :layout}
      end 

      post '/rules/repl' do
        content_type :json
        code = params[:ruby]
        r = Rules.new(org.syntax)

        begin
          r.eval_string(code)
        rescue Exception => e
          return {errors:e}.to_json
        end

        rs = RuleEngine.new(r)
        {results: rs.find_matches(org.all_transactions).flatten.map{|t| t.data}}.to_json
      end

      get '/transaction/:id' do |id|
        results = get_cached_books.all_transactions.select{|t| t.lookup_key == id}
        slim :'transaction/details', {:layout => :layout, :locals => {:results => results, :txn => results.first, :key => id}}
      end 

    end
  end
end
