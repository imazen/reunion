# Support for your bank or credit card

Currently we support PayPal, PNC bank, Chase Credit Cards, and American Express.

Adding support for new banks is trivial - if their data is accurate. The hard part is understanding your bank's quirks and accomodating them.

Here's the full implementation of PNC statement import. Note that the first row is a totally different schema

```ruby 
  class PncStatementActivityCsvParser < ParserBase
    def parse(text)
      # account number, startdate, enddate, startbalance, endbalance
      # date, value, description, blank, transaction, credit/debit
      a = CSV.parse (text)

      statements = [{date: Date.parse(a[0][1]), balance: parse_amount(a[0][3])}, {date: Date.parse(a[0][2]), balance: parse_amount(a[0][4])}]

      a.shift

      transactions = a.map do |t|
        {date: Date.strptime(t[0], '%Y/%m/%d'), 
         amount: parse_amount(t[1]) * (t[5] == "DEBIT" ? -1 : 1),
         description: t[2],
         ref: t[4] }
      end

      {statements: statements, transactions: transactions}
    end 
  end
```


## Bank-specific details

### PayPal

Paypal has many unique features - 

Charges directly to someone's PayPal account show up the same as transfer/charges through your own PayPal account.

### PNC

PNC's most accurate export method is Online Statements -> Select month -> Activity Detail -> Export > Select CSV -> Download Now


PNC statement CSVs and the 90-day activity exports use totally different descriptions... they can't be merged.

### Chase


Chase Jot CSVs include authorizations that's didnt't actually post.
Chase qfx exports include incorrect balances.
Use Chase Statement pdf ending balances for manual balance reconciliation.
Use Chase csv exports for transaction source.
