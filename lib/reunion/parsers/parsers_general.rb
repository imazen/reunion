
module Reunion
  class OfxParser < ParserBase
    def parse(text)
      transactions = []
      statements = []
      OFX(StringIO.new(text)) do
        statements << {date: account.balance.posted_at, balance: account.balance.amount}
        transactions += account.transactions.map do |t|
          {amount: t.amount, date: Date.parse(t.posted_at.to_s), description: t.name, description2: t.memo}
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

  class CsvParser < ParserBase
    def parse(text)
      a = CSV.parse(text.rstrip, csv_options).select{|r|true}

      {combined: a.map {|r|
        row = {}.merge(r.to_hash)
        json = JSON.parse(r[:json]) if r[:json] && !r[:json].strip.empty?
        row = row.merge(json) if json
        row
      }}
    end 
  end


  class TsvParser < ParserBase
    def parse(text)
      a = StrictTsv.new(text.encode('UTF-8').rstrip).parse

      {combined: a.map{|r|
        row = {}.merge(r)
        #merge JSON row
        json = JSON.parse(r[:json]) if r[:json] && !r[:json].strip.empty?
        row = row.merge(json) if json
        row
      }} 
    end 
  end



end


