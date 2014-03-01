require "sinatra"
require "slim"
module Reunion
  module Web
    class App < ::Sinatra::Base

      set :root, File.dirname(__FILE__)


      helpers do
        def get_date_from
          @@date_from ||= Date.parse('2013-01-01')
        end

        def get_date_to
          @@date_to ||= Date.parse('2014-01-01')
        end

      end 

      def filter_transactions(txns)
        txns.select do |t| 
          keep = true
          keep =  false if get_date_from && t.date < get_date_from
          keep =  false if get_date_to && t.date > get_date_to
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
        b = Reunion::ImazenBooks.new
        b.configure
        b.load
        b.rules
        b
      end

      def get_cached_books
        @@books ||= get_books
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




    get '/search' do
      slim :search, {layout: :layout, :locals => {:query => ""}}
    end

    get '/search/:query' do |query|
      filter_transactions(get_cached_books.all_transactions).select{|t| t.description.downcase.include?(query.downcase)}

      slim :search, {:layout => :layout, :locals => {:results => results, :query => query}}
    end

    get '/expense/?' do
      list = get_cached_books.all_transactions.map{|t| t[:tax_expense]}.uniq
      slim :expense, {layout: :layout, :locals => {:query => "", :tax_expense_names => list}}
    end

    get '/expense/:query' do |query|
      list = get_cached_books.all_transactions.map{|t| t[:tax_expense]}.uniq
      query = query.to_s.downcase.to_sym


      results = filter_transactions(get_cached_books.all_transactions).select{|t| query == :none ? t[:tax_expense].to_s.empty? : t[:tax_expense] == query}

      slim :expense, {:layout => :layout, :locals => {:results => results, :query => query, :tax_expense_names => list}}
    end



  end
end
end
