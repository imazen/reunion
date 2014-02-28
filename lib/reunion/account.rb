module Reunion
  class Account

    def initialize(name, currency, tags)
      @name = name
      @currency = currency
      @tags = tags
      @input_files = []
    end

    attr_accessor :name, :currency, :tags

    attr_accessor :input_files, :transactions, :statements, :final_discrepancy


    #Deletes any transactions in 'secondary_files' that have a similar transaction in primary_files (same date and amount)
    #returns an array of deleted transactions
    def delete_overlaps(primary_files, secondary_files)
      rejected = []
      secondary_files.each do |sf|
        sf.transactions.reject! do |txn|
          #For speed, check if there is a date overlap first
          overlaps_date = primary_files.any?{|f| f.first_txn_date <= txn[:date] && f.last_txn_date >= txn[:date]}
          other_exists = overlaps_date && primary_files.any?{|f| f.transactions.any?{|t| t[:date] == txn[:date] && t[:amount] == txn[:amount]}}
          rejected << txn if other_exists
          other_exists
        end
        ##Todo - update first_txn_date and last_txn_date now that they have changed?
      end

      rejected
    end


  end
end 
