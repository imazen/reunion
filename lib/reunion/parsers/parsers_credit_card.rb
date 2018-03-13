module Reunion

  # Merchant names will be longer, different. You may still need to account for that
  # when merging with other sources
  class ChaseCopyPasteStatementParser < ParserBase
    def parse(text)
      current_year = nil
      {transactions: 
        text.each_line.map do |line|
          line.strip!
          if  /^20[0-9][0-9]$/ =~ line
            current_year = line
            nil
          elsif line.empty?
            nil
          elsif current_year.nil?
            raise "File must contain a line with the year before any transactions"
          else
            parts = line.split(/\s+/)
            if parts.length < 3
              raise "Bad line #{line}"
            else 
              date = parts[0]
              if date.scan(/\//).count < 2
                date = "#{date}/#{current_year}"
              end 
              {date:  Date.strptime(date, '%m/%d/%Y'), 
                description: parts[1..-2].join(' '),
                amount: parse_amount(parts[-1]) * -1
              }
            end 
          end   
        end.compact
      }
    end
  end 
  class ChaseCsvParser < ParserBase

    def parse_txn_type(type)
      return nil if type.nil?
      case type.strip.downcase
      when "sale"
        :purchase
      when "return"
        :return
      when "payment"
        :transfer
      else
        nil
      end 
    end

    def parse(text)

      a = CSV.parse(text, csv_options)
      # Type,Trans Date,Post Date,Description,Amount
      # SALE,09/16/2013,09/18/2013,"ADOBE SYSTEMS, INC.",-32.09
      {transactions: 
        a.map { |l| 
          {date:  Date.strptime(l[:post_date], '%m/%d/%Y'), 
            description: l[:description], 
            amount: parse_amount(l[:amount]), 
            txn_type: parse_txn_type(l[:type]),
            chase_type: l[:type] ? l[:type].strip.downcase : nil }
        }.reverse
      }
    end
  end

  class AmexCsvParser < ParserBase

    def parse(text)

      a = CSV.parse(text, {headers: [:date, nil, :description, :holder_name, :card_number, nil, nil, :amount]})

      #01/01/2017  Sun,,"MICROSOFT - 800-642-7676, TX","Nathanael Jones","XXXX-XXXXXX-61006",,,64.77,,,,,,,,
      {transactions: 
        a.map { |l| 
          {date:  Date.strptime(l[:date], '%m/%d/%Y %a'), 
            description: l[:description], 
            amount: parse_amount(l[:amount]) * -1
          }
        }.reverse
      }
    end
  end

  
  class ChaseJotCsvParser < ChaseCsvParser
    
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
          txn_type: parse_txn_type(l[:type]),
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
end 