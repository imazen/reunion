module Reunion
  class InputFile
    attr_accessor :path, :full_path, :account_tag, :parser_tag, :account, :parser

    attr_accessor :transactions, :statements, :first_txn_date, :last_txn_date, :invalid_transactions
    
    attr_accessor :metaonly

    def path_account_digest
      Digest::SHA1.hexdigest(path.to_s + "|" + (account.nil? ? "nil" : account.permanent_id.to_s))
    end

    def load(schema)
      text = IO.read(full_path)
      results = parser.new.parse_and_normalize(text, schema)

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

      dates = transactions.map{|t| t[:date]}.uniq.compact.sort

      @first_txn_date = dates.first
      @last_txn_date = dates.last
    end

    def write_normalized(tag)
      dest_path = full_path + (tag == :USD ? ".normal.txt" : ".#{tag.to_s}.normal.txt")
      #full_path.chomp(File.extname(full_path)) + "." + tag.to_s + ".normal.txt"
      combined = (transactions + statements).reject{|v| v[:discard]}.stable_sort_by{|v| v.date.iso8601}

      output = Export.new.input_file_to_tsv(combined)
      File.open(dest_path, 'w') {|f| f.write(output)}
    end
  end
end
