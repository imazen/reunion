module Reunion
  class ChaseJotCsvParser < ParserBase
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

  class ChaseCsvParser < ParserBase
    def parse(text)

      a = CSV.parse(text, csv_options)
      # Type,Trans Date,Post Date,Description,Amount
      # SALE,09/16/2013,09/18/2013,"ADOBE SYSTEMS, INC.",-32.09
      {transactions: 
        a.map { |l| 
          {date:  Date.strptime(l[:post_date], '%m/%d/%Y'), 
            description: l[:description], 
            amount: parse_amount(l[:amount]), 
            chase_type: l[:type] }
        }.reverse
      }
    end
  end
end 