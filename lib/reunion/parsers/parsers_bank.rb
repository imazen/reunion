module Reunion
  class PncActivityCsvParser < ParserBase
    def parse(text)
      # Date,Description,Withdrawals,Deposits,Balance
      t = CSV.parse(text,**csv_options)
      t.delete_if { |l| l[:date].nil? && l[:amount].nil?}

      txns = t.map{ |l| 
        {date: Date.strptime(l[:date], '%m/%d/%Y'), 
          description: l[:description], 
          amount: parse_amount(l[:deposits]) - parse_amount(l[:withdrawals]), 
          balance_after: parse_amount(l[:balance]) }
        }
      txns.reverse!

      
      {transactions: txns }
    end 
  end

# from activity search export
  class ChaseActivityCsvParser < ParserBase
    def parse(text)
      # Details,Posting Date,"Description",Amount,Type,Balance,Check or Slip #,
      t = CSV.parse(text,**csv_options)
      t.delete_if { |l| l[:posting_date].nil? && l[:amount].nil?}


      txns = t.map{ |l| 
        desc = l[:description]
        if l[:check_or_slip]
          desc = "#{l[:description]} Check #{l[:check_or_slip]}"
        end 

        row = {date: Date.strptime(l[:posting_date], '%m/%d/%Y'), 
          description: desc.strip, 
          txn_type: l[:type],
          amount: parse_amount(l[:amount]), 
          balance_after: parse_amount(l[:balance], default: nil) }
        
        if row[:balance_after].nil? then row.delete(:balance_after) end
        row
      }
      txns.reverse!

      
      {transactions: txns }
    end 
  end


  class PncStatementActivityCsvParser < ParserBase
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

      {statements: statements, transactions: transactions}
    end 
  end
end 