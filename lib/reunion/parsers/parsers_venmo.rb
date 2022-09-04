
# Account Statement - (@lilithriver) - March 27th to June 26th 2021 ,,,,,,,,,,,,,,,,,,
# Account Activity,,,,,,,,,,,,,,,,,,
# ,ID,Datetime,Type,Status,Note,From,To,Amount (total),Amount (tip),Amount (fee),Funding Source,Destination,Beginning Balance,Ending Balance,Statement Period Venmo Fees,Terminal Location,Year to Date Venmo Fees,Disclaimer
# ,,,,,,,,,,,,,$8.00,,,,,
# ,3240312810181230868,2021-03-29T18:43:08,Payment,Complete,Laser,Lilith River,Brenda Mendez,- $20.00,,,Visa Debit *0040,,,,,Venmo,,
# ,3246271269313708750,2021-04-07T00:01:31,Payment,Complete,Cleaning,Lilith River,Veronica Cornelio,- $90.00,,,Visa Debit *0040,,,,,Venmo,,

module Reunion
  class VenmoCsvParser < ParserBase
    def parse_date(text)
      Date.iso8601(text)
    rescue Date::Error
      $stderr << "trying to parse date '#{text}'"
      raise
    end 

    def parse(text)
      csv_part = text.sub(/\AAccount Statement[^\n]+\nAccount Activity[^\n]+\n/, '')
      
      if csv_part.length == text.length
        older_header = text.include?('ID,Datetime,Type,Status,Note,From,To,Amount (total),Amount (fee),Funding Source,Destination')
        raise "Missing the Account Statement/Account Activity header for Venmo csv, got #{text[0..100]}" unless older_header
      end 

      a = CSV.parse(csv_part,**csv_options)
      {transactions:
        a.map do |l|
          parse_row(l)
        end.flatten.reverse
      }
    end

    def parse_txn_type(type)
      return :charge if type ==  "charge" 

      return :payment if type == "payment"

      s = type.strip.downcase.to_sym
      s = :refund if s == :'refunded transaction'
      s = :payment if s == :'merchant transaction'
      s = :transfer if s == :'standard transfer'
      if [:payment, :charge, :refund, :transfer].include?(s)
        s
      else
        raise "Unsupported Venmo transaction type #{type}. Please implement"
      end
    end
    def parse_status(status)
      return nil if status.nil?
      return :complete if status ==  "Complete"

      return :pending if status == "Pending"

      s = status.strip.downcase.to_sym

      # Because venmo, insane that it is, doesn't include failed transactions but leaves the status as 'failed' even for transient errors
      s = :complete if s == :failed

      # We don't care if it's refunded later, it was completed and affected the balance in the meantime
      s = :complete if s == :refunded

      s = :complete if s == :issued

      if [:pending, :complete].include?(s)
        s
      else
        raise "Unsupported Venmo transaction status #{status}. Please implement"
      end 
    end

    #Venmo balance

    def parse_venmo_amount(text)
      return nil if text.nil? || text.empty?
      parse_amount(text.gsub(/[ $]/,''))
    end 


    def parse_row(l)

      # Some rows have no datetime, just a balance
      return [] if l[:datetime].nil? || l[:datetime].empty?

      status = parse_status(l[:status])
      # Skip anything pending
      return [] if status == :pending

      # Parse the transaction type (charge, payment, refund)
      txn_type = parse_txn_type(l[:type])
      
      # Parse the date
      date = parse_date(l[:datetime])

      # Parse amounts
      total = parse_venmo_amount(l[:amount_total])
      fee = parse_venmo_amount(l[:amount_fee]) || 0
      tip = parse_venmo_amount(l[:amount_tip]) || 0

      
      recipient = txn_type == :charge ? l[:from] : l[:to]

      note = l[:note]

      describe_exchange = txn_type == :charge ? "#{recipient} charged you via Venmo" : "#{recipient} was paid via Venmo"
      
      # You only ever get one of these two
      # target_account = Venmo balance WHEN you receive funds
      # target_account = something else WHEN you withdraw funds to checking, txn_type should be :transfer
      source_account = l[:funding_source] || ''
      target_account = l[:destination] || ''

      # Parse funding source
      # Amex Send Account - create offset transactions w/o transfer tag
      # Venmo balance - treat these normally
      # All others - create offset transactions with transfer tag

      balance_txn = source_account.strip.downcase == "venmo balance" || target_account.strip.downcase == "venmo balance"
      tag_as_transfer = source_account.strip.downcase != "amex send account" && target_account.strip.downcase != "amex send account"
      
      fee_desc = fee != 0 ? " (fee #{'%.2f' % fee})" : ''
      desc = "#{describe_exchange}#{fee_desc} for: #{note}"
      # Withdrawals to a bank account we handle differently
      if txn_type == :transfer
        return [{
          date: date,
          description: "Balance funds transferred to #{target_account}",
          description2: note,
          amount: total,
          transfer: true
        }]
      end 

      results = []

      unless balance_txn
        # Create matching txn for withdrawal from funding source
        results << {
          date:date,
          description: "VENMO FUNDING FOR* #{describe_exchange}, funded by #{source_account} for: #{note}",
          amount: total * -1,
          transfer: tag_as_transfer,
        }
      end

      results << {
          date: date,
          description: desc,
          amount: total
        }
      results
    end
  end
end
