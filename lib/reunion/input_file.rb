module Reunion
  class InputFile
    attr_accessor :path, :full_path, :account_tag, :parser_tag, :account, :parser

    attr_accessor :transactions, :statements, :first_txn_date, :last_txn_date, :invalid_transactions
    
    attr_accessor :metaonly

    attr_accessor :invalid_count, :total_count,:statement_count, :txns_used, :txns_ignored

    def path_account_digest
      Digest::SHA1.hexdigest("#{path.to_s}|#{(account.nil? ? "nil" : account.permanent_id.to_s)}")
    end

    def try_load_cached(old_files)
      old = old_files&.find{ |f| f.path == path }
      if old && old.full_path == full_path && old.account_tag == account_tag && old.parser_tag == parser_tag
        @transactions = old.transactions
        @invalid_transactions = old.invalid_transactions
        @statements = old.statements
        @invalid_count = old.invalid_count
        @total_count = old.total_count
        @statement_count = old.statement_count
        @txns_used = old.txns_used
        @txns_ignored = old.txns_ignored
        @first_txn_date = old.first_txn_date
        @last_txn_date = old.last_txn_date
        @metaonly = old.metaonly
        # @account = old.account
        # @parser = old.parser
        true
      else
        false
        # $stderr << "Failed to load cached file #{full_path}\n"
      end
    end

    

    def load(schema)
      text = IO.read(full_path)
      begin 
        results = parser.new.parse_and_normalize(text, schema)
      rescue
        $stderr << "\nError parsing #{full_path}\n"
        raise 
      end 

      @transactions = results[:transactions] || []
      @invalid_transactions = results[:invalid_transactions] || []
      @statements = results[:statements] || []
      @statements.each do |t|
        t[:source] = path.to_sym
      end
      @transactions.each do |t|
        t[:source] = path.to_sym
        t[:account_sym] = account.permanent_id
        t[:discard_if_unmerged] = true if metaonly
      end

      dates = transactions.map {|t| t[:date] }.uniq.compact.sort
      @invalid_count = invalid_transactions.count
      @total_count = @transactions.count
      @statement_count = @statements.count
      @first_txn_date = dates.first
      @last_txn_date = dates.last
    end

    def write_normalized(tag)
      dest_path = full_path + (tag == :USD ? ".normal.txt" : ".#{tag}.normal.txt")
      # full_path.chomp(File.extname(full_path)) + "." + tag.to_s + ".normal.txt"
      combined = (transactions + statements).reject{ |v| v[:discard] }.stable_sort_by { |v| v.date.iso8601 }

      output = Export.new.input_file_to_tsv(combined)
      File.open(dest_path, 'w') { |f| f.write(output) }
    end
  end
end
