module Reunion
  class OfxParser < ParserBase
    def parse(text)
      transactions = []
      statements = []
      OFX(StringIO.new(text)) do
        accounts.each do |account|
          statements << { date: account.balance.posted_at, balance: account.balance.amount }
          transactions += account.transactions.map do |t|
            { amount: t.amount, date: Date.parse(t.posted_at.to_s), description: t.name, description2: t.memo }
          end
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
      a = CSV.parse(text.rstrip, **csv_options).select { |r| true }

      { combined: a.map { |r|
        row = {}.merge(r.to_hash)
        json = parse_json(r[:json])
        row = row.merge(json) if json
        row
      }}
    end
  end


  class TsvParser < ParserBase
    def parse(text)
      a = StrictTsv.new(text.encode('UTF-8').rstrip).parse

      {
        combined: a.map{|r|
          row = {}.merge(r)
          #merge JSON row
          json = parse_json(r[:json])
          row = row.merge(json) if json
          row
        }
      } 
    end 
  end

  class ManualAccountActivityTsvParser < TsvParser
    
    def parse(text)
      results = super(text)
      results[:combined] = results[:combined].map do |t|
        row = {}.merge(t)
        row[:balance] = !row[:balance].nil? && !row[:balance].strip.empty? ? parse_amount(row[:balance]) : nil
        row[:amount] = !row[:amount].nil? && !row[:amount].strip.empty? ? parse_amount(row[:amount]) : nil
        row[:date] = Date.parse(row[:date])
        raise "Make sure your tabs haven't been converted to spaces, missing both Amount and Balance columns #{row.inspect}" if !row.has_key?(:amount) && !row.has_key?(:balance)

        row
      end
      results
    end
  end

  class OwnerExpenseUtil < CsvParser
    def fixup_transactions(results)
      results[:combined] = results[:combined].map do |t|
        contrib = t.slice(:amount, :date, :description, :currency, :account_sym, :source, 
          :schema)
        
        raise "\nExpense row missing amount column: #{contrib.inspect}\n" if contrib[:amount].nil?
        
        contrib[:subledger] = :owner_contrib
        contrib[:tax_expense] = :owner_contrib
        contrib[:description] = "Owner contrib: #{contrib[:description]}"
        contrib[:amount] = parse_amount(contrib[:amount]) * -1
        [contrib,t]
      end.flatten
      results
    end
  end 
  class OwnerExpenseCsvParser < CsvParser
    def parse(text)
      OwnerExpenseUtil.new.fixup_transactions(super(text))
    end
  end

  class OwnerExpenseTsvParser < TsvParser
    def parse(text)
      OwnerExpenseUtil.new.fixup_transactions(super(text))
    end
  end


  class MetadataTsvParser < TsvParser
    def parse(text)
      results = super(text)
      results[:combined].each do |t|
        t[:discard_if_unmerged] = true
      end 
      results
    end
  end
end


