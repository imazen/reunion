module Reunion
  class PncActivityCsvParser < ParserBase
    def parse(text)
      # Date,Description,Withdrawals,Deposits,Balance
      t = CSV.parse(text, csv_options)
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