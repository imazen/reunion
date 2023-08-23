module Reunion
  class BankAccount

    def initialize(name: nil, currency: :USD, permanent_id: nil)
      @name = name
      @currency = currency.to_s.upcase.to_sym
      @permanent_id = permanent_id
      @input_files = []
      @overlap_deletions = []
      @drop_other_currencies = true
      @sort = nil
    end

    attr_accessor :name, :currency, :permanent_id, :drop_other_currencies, :truncate_before, :truncate_after

    attr_accessor :input_files, :transactions, :statements, :final_discrepancy, :schema, :sort


    def add_parser_overlap_deletion(keep_parser: nil, discard_parser: nil)
      @overlap_deletions << {keep: keep_parser, discard: discard_parser}
    end 


    def drop_transactions_before(date)
      @truncate_before = date
    end 

    def drop_transactions_after(date)
      @truncate_after = date
    end 

    #Finds any transactions in 'secondary_files' that have a similar transaction in primary_files (same date and amount)
    #returns an array of transactions
    def find_overlaps(primary_files, secondary_files)
      secondary_files.map do |sf|
        sf.transactions.select do |txn|
          #For speed, check if there is a date overlap first
          overlaps_date = primary_files.any?{|f| f.first_txn_date <= txn.date && f.last_txn_date >= txn.date}
          #Then cross-reference all transactions against each other. (O n^2)
          overlaps_date && primary_files.any?{|f| f.transactions.any?{|t| t.date == txn.date && t.amount == txn.amount}}
        end 
      end.flatten
    end

    def load_and_merge(schema: , remove_processor_prefixes: nil, transaction_modifier: nil)
      @schema = schema || @schema


      slow_prefixes = remove_processor_prefixes&.select { |prefix| !prefix.include?('*') }

      #1 thread per source file, 
      @input_files.map do |af|
        af.load(schema)
        af.transactions.each do |txn|
          # Filter out processor prefixes
          unless remove_processor_prefixes.nil?
            desc = txn[:description]
            prefixes_to_check = desc.include?('*') ? remove_processor_prefixes : slow_prefixes
            prefixes_to_check.each do |prefix|
              desc.delete_prefix!(prefix)
            end
            desc.lstrip!
            txn[:description] = desc
          end
          
          #Set default currency
          txn[:currency] ||= currency

          # Use the last transaction date for the priority
          txn[:priority] ||= af.last_txn_date

          # Call the configured lambda
          transaction_modifier&.call(txn)
        end

        #Drop other currencies if so configured
        if @drop_other_currencies
          currency_mismatch = af.transactions.select{|t| t[:currency] != currency && t[:currency].to_s.upcase.to_sym != currency }
          currency_mismatch.each { |t| t[:discard] = true; t[:discard_reason] = "Transaction currency (#{t[:currency]} doesn't match bank (#{currency}"}
        end

      end

      #Discard any overlaps configured between parsers
      @overlap_deletions.each do |pair|
        overlapped = find_overlaps(@input_files.select{|f| f.parser == pair[:keep]}, 
                      @input_files.select{|f| f.parser == pair[:discard]})

        overlapped.each {|t| t[:discard] = true; t[:discard_reason] = "Transaction (from #{pair[:keep]} overlapped one parsed with #{pair[:discard]}"}
      end

      #Concatenate account transactions
      txns = @input_files.map{|af| af.transactions}.flatten.compact

      #Exclude transactions prior to cut-off date
      txns.each do |t|
        if t.date < truncate_before
          t[:discard] = true; t[:discard_reason] = "Dropping transactions prior to " + truncate_before.strftime("%Y-%m-%d")
        end
      end if truncate_before
      txns.each do |t|
        if t.date > truncate_after
          t[:discard] = true; t[:discard_reason] = "Dropping transactions after " + truncate_after.strftime("%Y-%m-%d")
        end
      end if truncate_after

      #Exclude discarded transactions
      txns = txns.select{|t| t[:discard].nil?}

      @input_files.each do |af|
         af.write_normalized(currency)
      end 
      

      #Merge duplicate transactions from different sources
      txns = merge_duplicate_transactions(txns)

      txns = sort_transactions_and_statements(txns)

      #Assign sub-indexes to 'duplicate' transactions so we can reference them in a persistent manner
      OverrideSet.set_subindexes(txns)


      @transactions = txns
      @statements = @input_files.map{|af| af.statements}.flatten.compact
    end 


    def sort_transactions_and_statements(txns)
      if sort == :standard || (!!sort == sort && sort)
        txns.stable_sort_by do |t|
          next t.date_str if t.is_a?(Statement)
          "#{t.date_str}|#{t.description.strip.squeeze(' ').downcase}|#{'%.2f' % t.amount}"
        end
      elsif sort.is_a?(Symbol)
        txns.stable_sort_by{|t| t[sort]}
      elsif sort.is_a?(Array)
        txns.stable_sort_by{|t| sort.map{|k| t[k]}}
      else
        txns
      end
    end 

    def normalized_transactions_report
      sorted = sort_transactions_and_statements(transactions + statements)
      Export.new.input_file_to_tsv(sorted, drop_columns:[:account_sym, :currency, :subindex, :schema, :priority])
    end

  end
end 
