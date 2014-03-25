require 'minitest/autorun'
require 'reunion'
module Reunion

  describe 'rule evaluation' do
    it 'should be fast' do 

      schema = TransactionSchema.new


      o = [('a'..'z'), ('A'..'Z')].map { |i| i.to_a }.flatten

      txns = []

      500.times do
        txns << Transaction.new(schema:schema, date: Date.today, amount: 0,description: string = (0...rand(20) + 5).map { o[rand(o.length)] }.join )
      end 

      v = Vendors.new(StandardRuleSyntax.new(schema))
      v.add_default_vendors
      v.add_default_vendors
      v.add_default_vendors
      re = RuleEngine.new(v)

      #RubyProf.start

      re.run(txns)

      #result = RubyProf.stop
      #printer = RubyProf::GraphPrinter.new(result)
      #printer.print(STDERR)

    end 
  end 
end