=begin
  
PayPal doesn't just have credits and debits. They have:

Add Funds from a Bank Account
ATM Withdrawal
ATM Withdrawal Reversal
Auction Payment Received
Auction Payment Sent
Canceled Fee
Canceled Payment
Canceled Transfer
Chargeback Settlement
Check Withdrawal from PayPal
Currency Conversion
Debit Card Cash Advance
Debit Card Purchase
Dividend From PayPal Money 
Market
Donation Received
Donation Sent
eCheck Received
eCheck Sent
Funds Added with a Personal Check
Guarantee Reimbursement
Payment Received
Payment Sent
PayPal
PayPal Balance Adjustment
Referral Bonus
Refund
Shopping Cart Item
Shopping Cart Payment Received
Shopping Cart Payment Sent
Subscription Payment Received
Subscription Payment Sent
Transfer Update to Add Funds from 
a Bank Account
Update to Debit Card Credit
Update to eCheck Received
Update to Payment Received
Update to Payment Sent
Update to Reversal
Update to Web Accept Payment 
Received
Virtual Debit Card Authorization
Virtual Debit Card Credit Received
Virtual Debit Card Purchase
Virtual Debt Card Credit Received
Web Accept Payment Received
Web Accept Payment Sent
Withdraw Funds to a Bank Account

=end

module Reunion
  class PayPalBalanceAffectingPaymentsTsvParser < ParserBase

    def parse_txn_type(type)
      type = type.strip.downcase
      case
      when type.end_with?("received") || type == "Website Payments Pro API Solution".downcase
        :income
      when type.end_with?("sent") || type.end_with?("purchase")
        :purchase
      when type == "temporary hold" || type == "currency conversion"
        :fee
      when type == "refund"
        :refund
      when type.end_with?(" a bank account") || 
              type.end_with?(" a personal check") || 
                type.start_with?("check withdrawl") ||
                type == "charge from credit card"
        :transfer
      else
        nil
      end 
    end

    def flatten_currency_conversion(transactions)
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

            from_txn = secondaries.find{|t| (t[:amount] == primary[:paypal_gross] * -1) && t[:currency] == primary[:currency]}
            to_txn = secondaries.find{|t| t[:currency] != primary[:currency]}
            if !from_txn.nil? && !to_txn.nil?

              primary[:other_currency_amount] = primary[:amount]
              primary[:other_currency] = primary[:currency]
              primary[:paypal_gross] = to_txn[:amount]
              
              primary[:currency] = to_txn[:currency]
              primary[:balance_after] = to_txn[:balance_after]

              estimate_rate = primary[:paypal_gross] / primary[:other_currency_amount]

              primary[:txn_fee] *= estimate_rate
              primary[:sales_tax] *= estimate_rate
              primary[:amount] = primary[:paypal_gross] - primary[:txn_fee]
           

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
      transactions
    end

    def separate_fees(transactions)
      transactions.map do |t|
        fee = t[:txn_fee]
        if fee != 0
          a = {}.merge(t)
          b = {}.merge(t)
          a[:balance_after] -= fee
          a[:amount] = a[:paypal_gross]


          b[:amount] = fee
          b[:id] = "#{t[:id]}_fee"
          b[:txn_type] = :fee
          b[:sales_tax] = 0
          b[:txn_fee] = 0
          b[:paypal_gross] = fee
          [a,b]
        else
          t
        end
      end.flatten
    end 

    def parse(text)
      # Paypal uses WINDOWS-1252 - or chinese, japanese, korean, or russian, depeding upon what you've set here:
      # https://www.paypal.com/ie/cgi-bin/webscr?cmd=_profile-language-encoding
      # No, there's no link, you have to visit the page directly


      text.encode!('UTF-8', 'WINDOWS-1252')



      # PayPal's sadistic jerks pad randomly headers with spaces, in 
      # addition to failing to escape characters in CSVs

      a = CSV.parse(text, csv_options.merge({col_sep:"\t"}))

      transactions = a.map do |r|

        datetime = DateTime.strptime("#{r[:date]}|#{r[:time]}|#{r[:time_zone]}", '%m/%d/%Y|%T|%z')

        {date: datetime, 
          amount: parse_amount(r[:net]), 
          balance_after: parse_amount(r[:balance]),
          id: r[:transaction_id],
          ref_id: r[:reference_txn_id],
          currency: r[:currency],
          description: r[:name].gsub(/[\u{80}-\u{ff}]/,''),
          to_email: r[:to_email_address],
          paypal_type:r[:type],
          txn_type: parse_txn_type(r[:type]),
          paypal_country: r[:country],
          sales_tax: parse_amount(r[:sales_tax]),
          txn_fee: parse_amount(r[:fee]),
          paypal_gross: parse_amount(r[:gross])
        }
      end
      transactions.reverse!
      transactions = flatten_currency_conversion(transactions)

      bad_rows = transactions.select{|t| t[:paypal_gross] + t[:txn_fee] != t[:amount] }
      if bad_rows.count > 0
        raise "Found #{bad_rows.count} where net + fee != gross!\n#{bad_rows.inspect}" 
      end

      transactions = separate_fees(transactions)

      return {transactions:transactions}
    end 
  end
end 
