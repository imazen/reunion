require "sinatra"
require "slim"
module Reunion
  module Web
    class App < ::Sinatra::Base

      set :root, File.dirname(__FILE__)


      def get_all_transactions
        b = Reunion::ImazenBooks.new
        b.configure
        b.load
        b.rules
        b.all_transactions
      end 
      def get_cached_transactions
        @@all ||= get_all_transactions
      end


      get '/search' do
        slim :search, {layout: :layout, :locals => {:query => ""}}
      end

      get '/search/:query' do |query|
        get_cached_transactions.select{|t| t.description.downcase.include?(query.downcase)}

        slim :search, {:layout => :layout, :locals => {:results => results, :query => query}}
      end

     get '/expense' do
        slim :expense, {layout: :layout, :locals => {:query => ""}}
      end

      get '/expense/:query' do |query|
        list = get_cached_transactions.map{|t| t[:tax_expense]}.uniq
        query = query.to_s.downcase.to_sym


        results = get_cached_transactions.select{|t| query == :none ? t[:tax_expense].to_s.empty? : t[:tax_expense] == query}
        
        slim :expense, {:layout => :layout, :locals => {:results => results, :query => query, :tax_expense_names => list}}
      end



    end
  end
end
