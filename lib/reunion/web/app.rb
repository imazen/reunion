require "sinatra"
require "slim"
module Reunion
  module Web
    class App < ::Sinatra::Base

      set :root, File.dirname(__FILE__)

      get '/search' do
        slim :search, layout: :layout
      end

      get '/search/:query' do |query|
        b = Reunion::ImazenBooks.new
        b.configure
        b.load
        b.rules
        results = b.all_transactions

        slim :search, {:layout => :layout, :locals => {:results => results, :query => query}}
      end



    end
  end
end
