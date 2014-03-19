module Reunion
  class Parser
    attr_reader :description, :export_steps

    def parse(text)
    end

    def parse_and_normalize(text)
      results = parse(text)
      transactions = results[:transactions]
      transactions.each do |t|
        begin
          t[:date] = t[:date].is_a?(String) ? Date.parse(t[:date]) : t[:date]
        rescue ArgumentError 
        end 
        t[:tax_expense] = nil if t[:tax_expense].to_s.empty?
        t[:tax_expense] = t[:tax_expense].to_sym unless t[:tax_expense].nil?
        t.delete(:tax_expense) if t[:tax_expense].nil?
        #collapse whitespace and trim whitespace in descriptions
        t[:description] = t[:description].gsub(/\s+/," ").strip unless t[:description].nil?
      end 
      invalid_transactions = transactions.select{|t| t[:date].is_a?(String)}
      transactions -= invalid_transactions
      results[:invalid_transactions] = invalid_transactions

      #Reverse transactions if they're not in ascending order
      if transactions.length > 0 && transactions.first[:date] > transactions.last[:date]
        puts " Transactions out of order! Reversing... "
        transactions.reverse!
      end

      transactions = transactions.map do |t| 
        t2 = Transaction.new 
        t2.data = t
        t2
      end
      results[:statements] ||= []

       results[:statements] =  results[:statements].map do |s|
        s2 = Statement.new
        s2.data = s
        s2
      end
      results[:transactions] = transactions

      results
    end

    def parse_amount(text)
      return 0 if text.nil? || text.empty?
      BigDecimal.new(text.gsub(/[\$,]/, ""))
    end

  end

  class OfxParser < Parser
    def parse(text)
      transactions = []
      statements = []
      OFX(StringIO.new(text)) do
        statements << {date: account.balance.posted_at, balance: account.balance.amount}
        transactions += account.transactions.map do |t|
          {amount: t.amount, date: Date.parse(t.posted_at.to_s), description: t.name }
        end 
      end
      {transactions: transactions.stable_sort_by { |t| t[:date].iso8601 }, statements: statements}
    end
  end

  class OfxTransactionsParser < OfxParser
    def parse(text)
      result = super(text)
      result[:statements] = [] #Drop statements
      result
    end
  end

  class CsvParser < Parser
    def csv_options
      {headers: :first_row, 
      header_converters: lambda { |h| 
        h.nil? ? nil : h.encode('UTF-8').downcase.strip.gsub(/\s+/, "_").gsub(/\W+/, "").to_sym}
      }
    end 
  end


  class ChaseJotCsvParser < CsvParser
    def parse(text)

      #Jot has irregular line endings

      a = CSV.parse(text.gsub(/\r\n?/, "\n"), csv_options)
      #Tag,"Expense Category","Transaction ID","Transaction Date","Post Date","Receipt","Merchant Name",Amount
      #"","Miscellaneous",112532868119,20130916,20130918,,"ADOBE SYSTEMS, INC.      ",32.09

      # Jot exports have duplicate transactions
      # 1 line per tag applied - we have to merge them
      # TODO - merge instead of discarding 
      {transactions: a.map { |l| 
        {
          date: Date.strptime(l[:post_date], '%Y%m%d'), 
          description: l[:merchant_name], 
          amount: -parse_amount(l[:amount]), 
          chase_type: l[:type],
          id: l[:transaction_id],
          chase_tag: l[:tag],
          discard_if_unmerged: true
           }
          
        }.reverse.uniq {|l| l[:id]}
      }

      #Jot exports also have incorrect amounts , so merging can be hard.
      #Jot doesn't remove authorizations that are later modified or not posted
    end 
  end

  class ChaseCsvParser < CsvParser
    def parse(text)

      a = CSV.parse(text, csv_options)
      # Type,Trans Date,Post Date,Description,Amount
      # SALE,09/16/2013,09/18/2013,"ADOBE SYSTEMS, INC.",-32.09
      return {transactions: a.map { |l| 
              {
                date:  Date.strptime(l[:post_date], '%m/%d/%Y'), 
                description: l[:description], 
                amount: parse_amount(l[:amount]), 
                chase_type: l[:type] }
              }.reverse
            }
    end 
  end

  class TsvParser < CsvParser
    def parse(text)
      a = CSV.parse(text.rstrip, csv_options.merge({col_sep:"\t"}))

      statements = a.select { |r| r[:amount].nil? && !r[:balance].nil? }
      transactions = a.select { |r| !r[:amount].nil? }


      p a.to_a if statements.length + transactions.length == 0

      statements  =statements.map do |r|
        {
        date: Date.parse(r[:date]), 
        balance: parse_amount(r[:balance]),
        currency: r[:currency]
        }
      end

      transactions = transactions.map do |r|
         
        {
         date: Date.parse(r[:date]), 
         amount: parse_amount(r[:amount]), 
         balance_after: parse_amount(r[:balance]),
         id: r[:id],
         currency: r[:currency],
         description: r[:description]
        }
      end
      return {transactions:transactions, statements: statements}

    end 
  end

  class CsvJsParser < CsvParser
    def parse(text)
      a = CSV.parse(text.rstrip, csv_options).select{|r|true}

      all = a.map do |r|
        row = {}.merge(r.to_hash)
        #p row
        row[:date] = Date.parse(r[:date]) if r[:date]
        row[:amount] = parse_amount(r[:amount]) if r[:amount]
        row[:balance_after] = parse_amount(r[:balance_after]) if r[:balance_after]
        row[:balance] = parse_amount(r[:balance]) if r[:balance]
        json = JSON.parse(r[:set]) if r[:set] && !r[:set].strip.empty?
        row = row.merge(json) if json
        row
      end 

      statements = all.select { |r| r[:amount].nil? && !r[:balance].nil? }
      transactions = all.select { |r| !r[:amount].nil? }


      p a if statements.length + transactions.length == 0

      return {transactions:transactions, statements: statements}

    end 
  end


  class StrictTsv
    attr_reader :contents
    def initialize(contents)
      @contents = contents
    end
     
    def parse
      headers = contents.lines.first.downcase.strip.split("\t").map{|h|
        h.strip.gsub(/\s+/, "_").gsub(/\W+/, "").to_sym
      }
      contents.lines.to_a[1..-1].map do |line|
        Hash[headers.zip(line.rstrip.split("\t"))]
      end
    end
  
  end

  class TsvJsParser < CsvParser
    def parse(text)
      a = StrictTsv.new(text.encode('UTF-8').rstrip).parse

      all = a.map do |r|
        row = {}.merge(r)
        row[:date] = Date.parse(r[:date]) if r[:date]
        row[:amount] = parse_amount(r[:amount]) if r[:amount]
        row[:balance_after] = parse_amount(r[:balance_after]) if r[:balance_after]
        row[:balance] = parse_amount(r[:balance]) if r[:balance]
        json = JSON.parse(r[:set]) if r[:set] && !r[:set].strip.empty?
        row = row.merge(json) if json
        row
      end 


      statements = all.select { |r| r[:amount].nil? && !r[:balance].nil? }
      transactions = all.select { |r| !r[:amount].nil? }


      p a if statements.length + transactions.length == 0

      return {transactions:transactions, statements: statements}

    end 
  end

  class PayPalBalanceAffectingPaymentsTsvParser < CsvParser
    def parse(text)
      # Paypal uses WINDOWS-1252 - or chinese, japanese, korean, or russian, depeding upon what you've set here:
      # https://www.paypal.com/ie/cgi-bin/webscr?cmd=_profile-language-encoding
      # No, there's no link, you have to visit the page directly


      text.encode!('UTF-8', 'WINDOWS-1252')



      # PayPal's sadistic jerks pad randomly headers with spaces, in 
      # addition to failing to escape characters in CSVs

      a = CSV.parse(text, csv_options.merge({col_sep:"\t"}))

      transactions = a.map do |r|
         
        {date: Date.strptime(r[:date], '%m/%d/%Y'), 
          amount: parse_amount(r[:net]), 
          balance_after: parse_amount(r[:balance]),
        id: r[:transaction_id],
        ref_id: r[:reference_txn_id],
        currency: r[:currency],
        description: r[:name].gsub(/[\u{80}-\u{ff}]/,''),
        to_email: r[:to_email_address],
          paypal_type:r[:type],
          paypal_country: r[:country]
        }
      end
      transactions.reverse!

      with_refs = transactions.select{|t| t[:ref_id]}
      ref_ids = with_refs.map{|t| t[:ref_id]}
      refd = transactions.select{|t| ref_ids.include?(t[:id])}

      # Flatten Currency Conversion
      refd.each do |primary|
        secondaries = with_refs.select{|t| t[:ref_id] == primary[:id]}

        non_primary_currency = secondaries.select{|t| t[:currency] != primary[:currency]}
        if secondaries.all?{|t| t[:paypal_type] == "Currency Conversion"} && 
            secondaries.length == 2 &&
            primary[:paypal_type] != "Withdraw Funds to a Bank Account"

            from_txn = secondaries.find{|t| t[:amount] == primary[:amount] * -1 && t[:currency] == primary[:currency]}
            to_txn = secondaries.find{|t| t[:currency] != primary[:currency]}
            if !from_txn.nil? && !to_txn.nil?
              primary[:other_currency_amount] = primary[:amount]
              primary[:other_currency] = primary[:currency]

              primary[:amount] = to_txn[:amount]
              primary[:currency] = to_txn[:currency]
              primary[:balance_after] = to_txn[:balance_after]
              transactions.delete(to_txn)
              transactions.delete(from_txn)
              puts "Flattened " +  Transaction.new(primary).to_long_string
            end 
        
        end
      end 


      with_refs = transactions.select{|t| t[:ref_id]}
      ref_ids = with_refs.map{|t| t[:ref_id]}
      refd = transactions.select{|t| ref_ids.include?(t[:id])}

      refd.each do |primary|
        puts "\n"
        puts Transaction.new(primary).to_long_string
        with_refs.select{|t| t[:ref_id] == primary[:id]}.each do |reft|
          puts Transaction.new(reft).to_long_string
        end
      end 



      return {transactions:transactions}
    end 
  end

  class PncActivityCsvParser < CsvParser
    def parse(text)
      
      t = CSV.parse(text, csv_options)
      t.delete_if { |l| l[:date].nil? && l[:amount].nil?}

      txns = t.map{ |l| 
        {date: Date.strptime(l[:date], '%m/%d/%Y'), 
          description: l[:description], 
          amount: parse_amount(l[:deposits]) - parse_amount(l[:withdrawals]), 
          balance_after: parse_amount(l[:balance]) }
        }
      txns.reverse!

      # Date,Description,Withdrawals,Deposits,Balance
      r = {transactions: txns }
      #p txns 
      r
    end 
  end


  class PncStatementActivityCsvParser < CsvParser
    def parse(text)
      # account number, startdate, enddate, startbalance, endbalance
      # date, value, description, blank, transaction, credit/debit
      a = CSV.parse (text)

      statements = [{date: Date.parse(a[0][1]), balance: parse_amount(a[0][3])}, {date: Date.parse(a[0][2]), balance: parse_amount(a[0][4])}]

      a.shift

      transactions = a.map do |t|
        {date: Date.strptime(t[0], '%Y/%m/%d'), 
         amount: parse_amount(t[1]) * (t[5] == "DEBIT" ? -1 : 1),
         description: t[2],
         ref: t[4] }
      end

      return {statements: statements, transactions: transactions}
    end 
  end
end



    
