# Reunion - do your accounting in a single day

Reunion is both a library and webapp for repeatable accounting, expense categorization, and reporting. 

Eliminate audit anxiety &mdash; produce deduction reports with evidence already attached. 

All work is described in the form of input transaction files, override files, and logic rules.

Can be re-run at any time when logic or categorization rules need to be corrected. As someone with limited accounting knowledge, I find myself perpetually correcting my processes.

## Features

* Import overlapping and unorganized QFX, CSV, TSV, TXT files from your bank, credit card, or PayPal.
* Multi-currency
* Merge metadata from multiple sources (Chase Jot, PayPal, Amazon, etc). 
* Precision transaction deduplication and sanitization
* Reconcile against monthly balances to prove correctness
* Customize your schema, then define your rules in clean DSL.
* Store manual corrections as a set of deltas. 
* Reunion :heart: Git - **See diffs of everything that changes** &mdash; know exactly what a new file or rule changes.

## Stages

### Parse and deduplicate

Input files are parsed, merged, and deduplicated. If an input file needs to be used for multiple accounts, use a unique filetag only used by those accounts. Every currency within an account is a separate account. I.e, PayPal with both USD and EUR balances is two accounts. 

Associated data files (like Jot) are merged. 

### Reconciliation

Sanity-check. Ensure transactions add up to balances. You should enter manual monthly balances from your bank/card statements to ensure there are no issues.

Discrepancies are identified and windowed to a particular time span.

Reconciliation helps catch duplicate or missing transactions. 

### Tagging and transfer detection

Rules help tag transactions

Rules identify likely transfers, rough matching pairs them.

### Generate reports/ledgers based on tagged transfers

We can generate tax and ledgers based on transaction tags

## Todo

Allows manual transfer pairing via shared guids
Add credit-card charge-back (REBILL) matching/handling
What terminology to differentiate between 'discard_if_unmatched' transactions like jot and authoritative transactions?
Add 'expectations system' to allow for financial planning (and to double as tag tagging rules)
Add 'evidence association' for inscrutable descriptions
Add real-time rule evaluation
Add transaction clustering
Add Amazon and E-junkie addendum integration

## Maybe todo

Warn user if two overlapping input files disagree (this should be caught by reconciliation anyway)

---



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




## Notes from earlier

All files and pastes go into 'unparsed' initially, each accompanied by a description of where they were sourced. (i.e, PNC business, CSV statement export). Each source description used in the past should populate the auto-complete list.


## Parsing

During parsing, the user views an unparsed file and assigns (a) a parsing definition and (b) an account. 

It may be possible to have the computer auto-detect files.

The file will be moved out of 'unparsed' into 'imported', and named '[accountname]-[parsealgorithm]-[YYYY-MM-DD of last transaction date]-[x days].ext', like 'pncb-pncactivitycsv-2013-09-20-365-days.csv'

A tab delimited file will be created with just transaction data, name [file.ext].normal.tsv

A JSON file will be created with any additional data, named .normal.json. The SHA1 hash of the source file will be included, along with the export version number.

## Importing

All files for an account are pulled into memory and merged. Duplicate transactions in the same source file will be considered 'not duplicate'. If 2 source files overlap, and within that overlap, do not contain the same transactions, errors will be logged (unless disabled for that parse definition).

Results will be sorted by date, and split/written to multiple files (monthly, quarterly, or yearly depending on config)


## Transfers

Transfers will be auto-detected and added 



