# Reunion - do your accounting in a day

Reunion is both a library and webapp for repeatable and verifiable accounting, expense categorization, and reporting. 

**Year-end accounting in one day** &mdash; automate with a DSL or edit with a streamlined web app.

**Automatic reconciliation** &mdash; never lose a transaction (or confidence in your data). Balances are perpetually checked against intermediate transactions.

**Reunion :heart: Git** &mdash; DIFF ALL THE THINGS

**Eliminate audit anxiety** &mdash; access deduction reports with evidence already attached.

All work is described in the form of input files, rules, and deltas. Re-calculate everything in udner a second.

Evolve your system as your accounting knowledge improves.

## We need help gathering use cases - open an issue and describe your needs!

## Features

* Import overlapping and unorganized QFX, CSV, TSV, TXT files from your bank, credit card, or PayPal.
* Multi-currency
* Merge metadata from multiple sources (Chase Jot, PayPal, Amazon, etc). 
* Precision transaction deduplication and sanitization
* Reconcile against monthly balances to prove correctness
* Customize your schema, then define your rules in clean DSL.
* Store manual corrections as a set of deltas. 
* Reunion :heart: Git - **See diffs of everything that changes** &mdash; know exactly what a new file or rule changes.
* Detect transfers between accounts

## Stages

1. Configure. Define Bank accounts, file->account/parser convention, and the schema
2. Input files are parsed & sanitized per Schema
3. Input files are merged and deduplicated to create each account. Associated data files (like Jot) are merged. 
4. Balance statements are checked against intermediate transactions to ensure none are missing or duplicated. 
5. Manual deltas (overrides) are applied
6. Rules are applied
7. Manual deltas are applied again
8. Transfers are matched
8. Results are generated


## Configuration

We'll have a sample project set up shortly after someone asks.

### Describe bank accounts

Describe the bank accounts you will be importing transactions for. 
```
paypal      = BankAccount.new(name: "PayPal", currency: :USD, permanent_id: :paypal)
paypal_euro = BankAccount.new(name: "PayPal_Euro", currency: :EUR, permanent_id: :paypal_euro)
chase       = BankAccount.new(name: "ChaseCC", currency: :USD, permanent_id: :chasecc)
amex        = BankAccount.new(name: "Amex", currency: :USD, permanent_id: :amex)
pnc         = BankAccount.new(name: "PNC", currency: :USD, permanent_id: :pnc)
@bank_accounts = [paypal, paypal_euro, chase, amex, pnc]
```
### Describe file naming convention for accounts and parsers

If you want to use the default convention and StandardFileLocator, each input file needs to be named `[account]-[parser]-humanname.ext`.

Map account tags to bank account instances
```
@bank_file_tags = {paypal: [paypal, paypal_euro], #because files tagged 'paypal' have both EUR and USD txns
                   paypal_usd: paypal, 
                   paypal_euro: paypal_euro,
                   chasecc: chase,
                   amex: amex,
                   pnc: pnc}
```

Map the parser tags to classes.
```
@parsers = {
  pncs: PncStatementActivityCsvParser,
  pncacsv: PncActivityCsvParser,
  ppbaptsv: PayPalBalanceAffectingPaymentsTsvParser,
  chasejotcsv: ChaseJotCsvParser,
  chasecsv: ChaseCsvParser,
  tsv: TsvParser,
  tjs: TsvJsParser,
  cjs: CsvJsParser,
  amexqfx: OfxParser,
  chaseqfx: OfxTransactionsParser}
```

Some account files can't be merged, and need to have overlaps deleted instead.

```
#Because PNC statements and activity exports have different transaction descriptions.
pnc.add_parser_overlap_deletion(keep_parser: PncStatementActivityCsvParser, discard_parser: PncActivityCsvParser)
```

Configure where to look for files

```
@locator = l = StandardFileLocator.new 
l.working_dir = File.dirname(__FILE__)
l.input_dirs = ["./input/imports","./input/manual","./input/categorize"]
```

### Describe the schema

Fields defined in the schema can be indexed and searched with the DSL. They also can be exposed for manual editing in the web app, and can be (de)serialized with accuracy. Temporary fields that doesn't need any of these advantages can simply use the hash interface provided by all transactions.

The schema ensures that data types are verified at each stage. 

```
@schema = Schema.new({id: StringField.new(readonly:true),
 date: DateField.new(readonly:true, critical:true, display_tags: [:rebill_form]), 
 amount: AmountField.new(readonly:true, critical:true, default_value: 0, display_tags: [:rebill_form]),
 balance_after: AmountField.new(readonly:true),
 tags: TagsField.new,
 description: DescriptionField.new(readonly:true, default_value: "", display_tags: [:rebill_form]),
 description2: DescriptionField.new(readonly:true, display_tags: [:rebill_form]),
 vendor: SymbolField.new(display_tags: [:rebill_form]),
 vendor_description: DescriptionField.new,
 vendor_tags: TagsField.new,
 client: SymbolField.new,
 subledger: SymbolField.new,
 client_tags: TagsField.new,
 tax_expense: SymbolField.new(display_tags: [:rebill_form]),
 account_sym: SymbolField.new(readonly:true),
 transfer: BoolField.new,
 discard_if_unmerged: BoolField.new(readonly:true),
 currency: UppercaseSymbolField.new(readonly:true),
 chase_tags: TagsField.new,
 rebill: SymbolField.new(display_tags: [:rebill_form]),
 memo: DescriptionField.new(display_tags: [:rebill_form]),
 product: SymbolField.new(display_tags: [:rebill_form]),
 txn_type: SymbolField.new()
})
```

### Reconciliation

Sanity-check. Ensure transactions add up to balances. If your exported files don't inclue them, you should enter ending statement balances in a tab-delimited file, like this:

```
Date	Balance
2013-12-04	-3843.84
2014-01-04	-415.04
2014-02-04	-115.00
2014-03-04	-2,238.79
2014-03-25	-5245.79
```

Discrepancies are identified and windowed to a particular time span.

Reconciliation helps catch duplicate or missing transactions. 
