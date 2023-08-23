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

      a = CSV.parse(text,**csv_options)
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

      a = CSV.parse(text, **{headers: [:date, nil, :description, :holder_name, :card_number, nil, nil, :amount]})

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

  class NewAmexCsvParser < ParserBase

    def parse(text)

      a = CSV.parse(text,**csv_options)

      # Date,Reference,Description,Card Member,Card Number,Amount,Category,Type
      # 12/30/19,'320193640530997967',AUTOPAY PAYMENT - THANK YOU,LILITH RIVER,-61006,-657.37,,CREDIT

      {transactions:
        a.map { |l|
            {date:  Date.strptime(l[:date], '%m/%d/%y'),
            description: l[:description],
            amount: parse_amount(l[:amount]) * -1
          }
        }.reverse
      }
    end
  end

  class Amex20CsvParser < ParserBase
    #For 2020, when amex started using 4 year dates again
    def parse(text)

      a = CSV.parse(text,**csv_options)

      # Date,Receipt,Description,Card Member,Account #,Amount,Extended Details,Appears On Your Statement As,Address,City/State,Zip Code,Country,Reference,Category
      #12/31/2020,,APPVEYOR            VICTORIA            CA,LILITH RIVER,-61006,74.50,"NT_IG3TDCBR 17789898955
      #APPVEYOR
      #VICTORIA
      #CA
      {transactions:
        a.map { |l|
            {date:  Date.strptime(l[:date], '%m/%d/%Y'),
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

      a = CSV.parse(text.gsub(/\r\n?/, "\n"), **csv_options)
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

  class HomeDepotCommercialRevolvingCsvParser < ParserBase

    
    def parse(text)

      # CSV.parse without headers, array of arrays
      a = CSV.parse(text.gsub(/\r\n?/, "\n")) 
      
      start_at = -1
      
      # loop through lines until we find "Current Activity"
      a.each_with_index do |row, i|
        # case insensitive comparison with strip account for null
        if !row[0].nil? && row[0].strip.downcase == "current activity" 
          start_at = i + 1
          break
        end
      end

      # raise if we didn't find "Current Activity"
      if start_at == -1
        raise "Could not find 'Current Activity' in CSV"
      end

      # Loop, overlapping, through all consecutive cell pairs in rows of 'a' above Current Activity and for any where the where the first item contains alphabeta characters, add the pair to a hash
      metadata_pairs = {}
      a[0..start_at].each do |row|
        row.each_cons(2) do |pair|
          if !pair[0].nil? && !pair[1].nil? && pair[0] =~ /[a-zA-Z]/
            # if already exists, verify it matches after stripping whitespace
            # lowercase and underscore and convert to symbol for key
            k = pair[0].strip.downcase.gsub(/\s+/, "_").to_sym
            v = pair[1].strip
            if metadata_pairs.key?(k) && metadata_pairs[k] != v
              raise "Metadata key #{k} has multiple values: #{metadata_pairs[k]} and #{v}"
            end
            metadata_pairs[k] = v
          end
        end
      end

      # Parse "Closing Date" and "New Balance" from metadata_pairs
      closing_date = Date.strptime(metadata_pairs[:closing_date], '%m/%d/%Y')
      new_balance = parse_amount(metadata_pairs[:new_balance])

      #Raise error if Finance Charges and Late Fees don't parse to 0
      if parse_amount(metadata_pairs[:finance_charges]) != 0
        raise "Finance Charges not 0, add feature if there is no txn to represent this balance change"
      end
      if parse_amount(metadata_pairs[:late_fees]) != 0
        raise "Late Fees not 0, add feature if there is no txn to represent this balance change"
      end

      #Reparse all lines after Current Activity using headers.

      #First serialize the array of arrays into a CSV string
      csv_string = CSV.generate do |csv|
        a[start_at..-1].each do |row|
          csv << row
        end
      end

      #Then parse the CSV string into an array of hashes using headers 
      transactions = CSV.parse(csv_string, **csv_options)

      #Concatenate the date (format ''20-DEC'' with the year from the closing_date, then parse. If the date is after the closing date, subtract a year
      { transactions: transactions.map do |t|

          date = Date.strptime("#{t[:transaction_date]} #{closing_date.year}", '%d-%b %Y')
          if date > closing_date
            date = date.prev_year
          end
          # Add invoice number to description
          desc = t[:location_description]
          if t[:invoice_number]
            desc = "#{desc} Invoice #{t[:invoice_number]}"
          end
          {
            date: date,
            description: desc,
            amount: parse_amount(t[:amount]) * -1,
            invoice_number: t[:invoice_number]
          }
        end,
        statements: [{
          date: closing_date,
          balance: new_balance
        }]
        
      }
    end
  end

end
