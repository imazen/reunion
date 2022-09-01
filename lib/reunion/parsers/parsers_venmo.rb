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
 class VenmoCsvParser < ParserBase


    def parse_date(text)
      Date.iso8601(text)
    end 

    def parse(text)
      a = CSV.parse(text,**csv_options)
      {transactions: 
        a.map { |l| 
          parse_row(l)
        }.flatten.reverse
      }
    end

    def parse_row(l)
      date = parse_date(l[:datetime])


      amount = parse_amount(l[:amount_total])
      fee = parse_amount(l[:amount_fee])
      net = amount - fee

      is_request = l[:type].downcase == "charge" 
      raise "Invalid Venmo txn type #{l[:type]}" if !is_request && l[:type].downcase != "payment"

      #skip txns that haven't cleared
      if l[:status].nil? || l[:status].downcase != "complete"
        return [] 
      end 

      from = l[:from]
      to = l[:to]

      source = l[:funding_source]
      dest = l[:destination]


      recipient = amount > 0 

      desc =  l[:note]
      desc2 = l[:type].downcase == "charge" ? "#{l[:from] charged l[:to]} "




      l[:type]

      txn_type = parse_txn_type(l[:type])

    
      #if it lacks a transfer_date, then it probably hasn't landed in the bank yet
      # adjustment fee = chargeback fee
      results = []

      if fee != 0 then
        results << {
          date: date,
          description: desc,
          amount: 0 - fee,
          txn_type: :fee
        }
      end 
      #id,Type,Source,Amount,Fee,Net,Currency,Created (UTC),Available On (UTC),Description,Customer Facing Amount,Customer Facing Currency,Transfer,Transfer Date (UTC)
      #txn_19gkmR2kdGSXuqwcnYpNleXL,transfer,tr_19gkmR2kdGSXuqwcX85dZLPZ,-824.08,0.00,-824.08,usd,2017-01-28 01:13,2017-01-29 00:00,STRIPE TRANSFER,,,,
      #txn_18bB5g2kdGSXuqwcVm1fYE09,refund,ch_18BnYG2kdGSXuqwcGJj4i9MG,-249.00,-7.52,-241.48,usd,2016-07-25 15:34,2016-07-25 15:34,REFUND FOR CHARGE (Spree Order ID: R023318196-BGR5XETC),-249.00,usd,tr_18bNa22kdGSXuqwcZWRXdGRb,2016-07-27 00:00
      #txn_18XNw42kdGSXuqwc9ADfcRNe,transfer,tr_18XNw42kdGSXuqwcPblCB9xV,-824.08,0.00,-824.08,usd,2016-07-15 04:28,2016-07-16 00:00,STRIPE TRANSFER,,,tr_18XNw42kdGSXuqwcPblCB9xV,2016-07-18 00:00
      #txn_18X4XT2kdGSXuqwcBrHTyg2s,charge,ch_18X4XS2kdGSXuqwcFAw6Jwos,849.00,24.92,824.08,usd,2016-07-14 07:45,2016-07-16 00:00,Spree Order ID: R102903265-QUTV7T4D,849.00,usd,tr_18XNw42kdGSXuqwcPblCB9xV,2016-07-18 00:00
      #txn_18X1Qq2kdGSXuqwc07tcbbN7,transfer,tr_18X1Qq2kdGSXuqwc3t8R373F,864.00,0.00,864.00,usd,2016-07-14 04:26,2016-07-15 00:00,STRIPE TRANSFER,,,tr_18X1Qq2kdGSXuqwc3t8R373F,2016-07-15 00:00
      #txn_18Wt2c2kdGSXuqwcAk3BN2bS,adjustment,ch_18RUCq2kdGSXuqwcxuiNjYA4,-849.00,15.00,-864.00,usd,2016-07-13 19:29,2016-07-13 19:29,Chargeback withdrawal for ch_18RUCq2kdGSXuqwcxuiNjYA4,,,tr_18X1Qq2kdGSXuqwc3t8R373F,2016-07-15 00:00
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