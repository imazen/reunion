require 'minitest/autorun'
require 'reunion'

module Reunion

  describe Amex20CsvParser do

    before do
      
      @parser = Amex20CsvParser.new

      @csv_text = <<CSVEXAMPLE
      Date,Receipt,Description,Card Member,Account #,Amount,Extended Details,Appears On Your Statement As,Address,City/State,Zip Code,Country,Reference,Category
12/31/2020,,APPVEYOR            VICTORIA            CA,LILITH RIVER,-61006,74.50,"NT_IG3TDCBR 17789898955
APPVEYOR
VICTORIA
CA
17789898955",APPVEYOR            VICTORIA            CA,5460 ALDERLEY RD,"VICTORIA
BC",V8Y 1X8,CANADA,'320210010351785984',Business Services-Professional Services
12/31/2020,,GOOGLE *ADS314372931CC@GOOGLE.COM       CA,LILITH RIVER,-61006,500.00,"A0G2UTKU    ADVERTISING
GOOGLE *ADS3143729311
CC@GOOGLE.COM
CA
ADVERTISING",GOOGLE *ADS314372931CC@GOOGLE.COM       CA,"1600 AMPHITHEATRE PKWY
MOUNTAIN VIEW
CA",,94043-1351,UNITED STATES OF AMERICA (THE),'320203660333639981',Business Services-Advertising Services
12/30/2020,,ONLINE PAYMENT - THANK YOU,LILITH RIVER,-61006,-880.90,ONLINE PAYMENT - THANK YOU,ONLINE PAYMENT - THANK YOU,,,,,'320203650311426069',
CSVEXAMPLE

      @schema = Schema.new({
          date: DateField.new(readonly:true, critical:true), 
          amount: AmountField.new(readonly:true, critical:true, default_value: 0),
          description: DescriptionField.new(readonly:true, default_value: "")
      })

    end

    it 'should parse without errors' do
      @parser.parse(@csv_text)
    end

    it 'should parse and normalize' do
      @parser.parse_and_normalize(@csv_text, @schema)
    end

    it 'should produce valid date, description, and amounts' do
      @parser.parse_and_normalize(@csv_text, @schema)[:transactions].each do |t|
          assert t[:date].is_a?(Date)
          assert t[:description].is_a?(String)
          assert t[:amount].is_a?(BigDecimal)
      end
    end
  end

  describe HomeDepotCommercialRevolvingCsvParser do
    before do 
      @parser = HomeDepotCommercialRevolvingCsvParser.new
      @csv_text = <<CSVEXAMPLE
Account Number,************2838,,,
,,,,
Closing Date,01/13/2023,,,
Minimum Payment Due,$168.00,,,
Payment Due Date,02/08/2023,,,
,,,,
,Previous Balance,$0.00,Closing Date,01/13/2023
,Payments,-$0.00,Next Closing Date,02/10/2023
,Credits,-$0.00,Payment Due Date,02/08/2023
,Purchases,$2015.13,Current Payment Due,$168.00
,Debits,$0.00,Past Due,$0.00
,Finance Charges,$0.00,Total Payment Due,$168.00
,Late Fees,$0.00,Credit Line,$25000.00
,New Balance,$2015.13,Credit Available,$22595.00
,Revolving Balance,$2015.13,,,
,60-day balances expiring this period,$0.00,,,
,60-day balances NOT expiring this period,$0.00,,,
,Amount to pay to avoid incurring finance charges,$2015.13,,,
,,,,
Current Activity,,,,
,Transaction Date,Location/Description,Amount,Invoice Number
,20-DEC, THE HOME DEPOT BROOMFIELD  CO,$338.77, 
,20-DEC, SEASONAL/GARDEN LUMBER DISCOUNT,$0.00, 
,20-DEC, THE HOME DEPOT BROOMFIELD  CO,$3.21, 
,20-DEC, SEASONAL/GARDEN,$0.00, 
,02-JAN, HOME DEPOT.COM 1-800-430-3376,$295.51, 
,02-JAN, PLUMBING,$0.00, 
,02-JAN, HOME DEPOT.COM 1-800-430-3376,$114.32, 
,02-JAN, PLUMBING,$0.00, 
CSVEXAMPLE
      @schema = Schema.new({
          date: DateField.new(readonly:true, critical:true), 
          amount: AmountField.new(readonly:true, critical:true, default_value: 0),
          description: DescriptionField.new(readonly:true, default_value: "")
      })
    end

    it 'should parse without errors' do
      @parser.parse(@csv_text)
    end

    it 'should parse and normalize' do
      @parser.parse_and_normalize(@csv_text, @schema)
    end

    it 'should produce valid date, description, and amounts' do
      parsed = @parser.parse_and_normalize(@csv_text, @schema)
      
      parsed[:transactions].each do |t|
          assert t[:date].is_a?(Date)
          assert t[:description].is_a?(String)
          assert t[:amount].is_a?(BigDecimal)
      end
    end

    it 'should produce valid statements' do
      parsed = @parser.parse_and_normalize(@csv_text, @schema)
      # expect equals 01/13/2023 and $2015.13

      parsed[:statements].each do |s|
        assert s[:date].is_a?(Date)
        assert s[:balance].is_a?(BigDecimal)

        _(s[:date]).must_equal(Date.strptime("01/13/2023", '%m/%d/%Y'))
        _(s[:balance]).must_equal(BigDecimal("2015.13"))
      end
    end

    it 'should fixup years for transactions' do
      parsed_txns = @parser.parse_and_normalize(@csv_text, @schema)[:transactions]

      #Check that 1 or more transactions exists for dec 20 2022 AND JAN 2 2023   
      found = parsed_txns.filter{|t| t[:date] == Date.strptime("12/20/2022", '%m/%d/%Y')}
      assert found.size > 0

      found_jan = parsed_txns.filter{|t| t[:date] == Date.strptime("01/02/2023", '%m/%d/%Y')}
      assert found_jan.size > 0
    end
  end
end

