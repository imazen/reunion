=begin
  
Type and ID of transaction (transfer, charge, adjustment, etc.)
Amount
Currency
Fees
Net amount
Date created
Date available
Description
Transfer ID
Transfer date

=end
# transactions always need to be split up when the fee column is populated

#type: transfer, charge, adjustment, refund 
#Transaction type: adjustment, application_fee, application_fee_refund, charge, payment, payment_failure_refund, payment_refund, refund, transfer, transfer_cancel, transfer_failure, transfer_refund, or validation.
#amount, fee, net
# Crash if currency != USD



module Reunion
  class StripeBalanceCsvParser < ParserBase

    def parse_txn_type(type)
      s = type.strip.downcase.to_sym
      s = :transfer if s == :payout
      s = :fee if s == :stripe_fee
      if [:transfer, :charge, :adjustment, :refund, :fee].include?(s)
        s
      else
        raise "Unsupported Stripe transaction type #{type}. Please implement"
      end 
    end



    def parse_date(text)
      Date.strptime("#{text} UTC", '%Y-%m-%d %H:%M %Z')
    end 

    def parse(text)
      a = CSV.parse(text, **csv_options)
      {combined: 
        a.map { |l| 
          parse_row(l)
        }.flatten.reverse
      }
    end

    def parse_row(l)
      available_date = parse_date(l[:available_on_utc] || l[:available_on])
      created_date = parse_date(l[:created_utc] || l[:created])
      
      date = available_date #created_date #available_date > Date.parse("2020-12-31") ? available_date : created_date
      desc =  l[:description]
      txn_type = parse_txn_type(l[:type])
      amount = parse_amount(l[:amount])
      fee = parse_amount(l[:fee])
      net = parse_amount(l[:net])
      raise "Stipe parse error: amount (#{amount}) - fee (#{fee} must equal net (#{net})" if (amount - fee) != net
      raise "Only USD support implemented for Stripe balance" if l[:currency] != "usd"

      #If transactions haven't had a chance to land in the bank yet, don't mess with them, it will cause discrepancies
      #if it lacks a transfer_date, then it probably hasn't landed in the bank yet
      if (l[:transfer_date_utc].nil? || l[:transfer_date_utc].empty?) &&
        (l[:transfer_date].nil? || l[:transfer_date].empty?)
        return [] #Skip rows that haven't landed in the bank yet. 
      end 


      #id,Type,Source,Amount,Fee,Net,Currency,Created (UTC),Available On (UTC),Description,Customer Facing Amount,Customer Facing Currency,Transfer,Transfer Date (UTC)
      #txn_19gkmR2kdGSXuqwcnYpNleXL,transfer,tr_19gkmR2kdGSXuqwcX85dZLPZ,-824.08,0.00,-824.08,usd,2017-01-28 01:13,2017-01-29 00:00,STRIPE TRANSFER,,,,
      #txn_18bB5g2kdGSXuqwcVm1fYE09,refund,ch_18BnYG2kdGSXuqwcGJj4i9MG,-249.00,-7.52,-241.48,usd,2016-07-25 15:34,2016-07-25 15:34,REFUND FOR CHARGE (Spree Order ID: R023318196-BGR5XETC),-249.00,usd,tr_18bNa22kdGSXuqwcZWRXdGRb,2016-07-27 00:00
      #txn_18XNw42kdGSXuqwc9ADfcRNe,transfer,tr_18XNw42kdGSXuqwcPblCB9xV,-824.08,0.00,-824.08,usd,2016-07-15 04:28,2016-07-16 00:00,STRIPE TRANSFER,,,tr_18XNw42kdGSXuqwcPblCB9xV,2016-07-18 00:00
      #txn_18X4XT2kdGSXuqwcBrHTyg2s,charge,ch_18X4XS2kdGSXuqwcFAw6Jwos,849.00,24.92,824.08,usd,2016-07-14 07:45,2016-07-16 00:00,Spree Order ID: R102903265-QUTV7T4D,849.00,usd,tr_18XNw42kdGSXuqwcPblCB9xV,2016-07-18 00:00
      #txn_18X1Qq2kdGSXuqwc07tcbbN7,transfer,tr_18X1Qq2kdGSXuqwc3t8R373F,864.00,0.00,864.00,usd,2016-07-14 04:26,2016-07-15 00:00,STRIPE TRANSFER,,,tr_18X1Qq2kdGSXuqwc3t8R373F,2016-07-15 00:00
      #txn_18Wt2c2kdGSXuqwcAk3BN2bS,adjustment,ch_18RUCq2kdGSXuqwcxuiNjYA4,-849.00,15.00,-864.00,usd,2016-07-13 19:29,2016-07-13 19:29,Chargeback withdrawal for ch_18RUCq2kdGSXuqwcxuiNjYA4,,,tr_18X1Qq2kdGSXuqwc3t8R373F,2016-07-15 00:00
      #txn_1Jtgz02kdGSXuqwcKLYFb21q,payout,po_1Jtgz02kdGSXuqwc69O4GIEp,-5000.00,50.00,,,-5050.00,usd,2021-11-08 23:10,2021-11-08 23:10,"",,,po_1JvX9I2kdGSXuqwc0RPYSJb8,2021-11-15 00:00,,,,
      
      #The CSV is newest to oldest, so we reverse this order later
      
      results = []
      if txn_type == :transfer && amount < 0 then
        # Payout should bring balance to zero 
        results << {
          date: date,
          balance: 0
        }
      end 
      if fee != 0 then
        # Payouts and charges and refunds can have fees
        # adjustment fee = chargeback fee
        results << {
          date: date,
          description: desc,
          amount: 0 - fee,
          txn_type: :fee
        }
      end 
      results << {
          date: date,
          description: desc,
          amount: amount,
          txn_type: txn_type
        }
      results
    end 
  end
end