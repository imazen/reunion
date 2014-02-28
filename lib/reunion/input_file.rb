class Reunion::InputFile
  attr_accessor :path, :full_path, :account_tag, :file_tag, :account, :parser

  attr_accessor :transactions, :statements, :first_txn_date, :last_txn_date


  def load
    text = IO.read(full_path)
    results = parser.new.parse_and_normalize(text)

    @transactions = results[:transactions]
        @statements = results[:statements] || []
        @statements.each do |t| 
            t[:source] = path.to_sym
        end
    @transactions.each do |t|
      t[:source] = path.to_sym
            t[:account_sym] = account_tag.downcase.to_sym
            puts "Failed to parse date #{t[:date]}" if t[:date].is_a?(String)
        end 

        dates = transactions.map{|t| t[:date]}.uniq.compact.sort

        @first_txn_date = dates.first
        @last_txn_date = dates.last
  end


end
