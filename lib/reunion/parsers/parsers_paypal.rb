module Reunion
  class PayPalBalanceAffectingPaymentsTsvParser < ParserBase
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
              #puts "Flattened " +  Transaction.new(from_hash: primary).to_long_string
            end 
        
        end
      end 


      with_refs = transactions.select{|t| t[:ref_id]}
      ref_ids = with_refs.map{|t| t[:ref_id]}
      refd = transactions.select{|t| ref_ids.include?(t[:id])}

      refd.each do |primary|
        #puts "\n"
        #puts Transaction.new(from_hash: primary).to_long_string
        with_refs.select{|t| t[:ref_id] == primary[:id]}.each do |reft|
          #puts Transaction.new(from_hash: reft).to_long_string
        end
      end 



      return {transactions:transactions}
    end 
  end
end 
