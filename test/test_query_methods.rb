require 'minitest/autorun'
require 'reunion'

module Minitest::Assertions
  def assert_tags_are_assigned(transactions, &block)
    schema = Reunion::TransactionSchema.new
    r = Reunion::Rules.new(Reunion::StandardRuleSyntax.new(schema))

    r.add(&block)

    transactions = transactions.map do |t|
      schema.normalize(Reunion::Transaction.new(schema:schema, from_hash: t))
    end 

    re = Reunion::RuleEngine.new(r)
    re.run(transactions)

    transactions.each do |t|
      assert_equal t[:expected_tags], t[:tags], re.tree.inspect + "\n\n" + r.inspect
    end 

  end
end 


module Reunion

  describe 'query methods' do


    
    
    it 'should handle date_between matches' do

      assert_tags_are_assigned(
        [{:date => '2012-02-01', 
        :amount => "20.00",
        :tags => [:a], :expected_tags => [:a, :found]},
        {:date => '2014-01-01', 
        :amount => "20.00",
        :tags => [:b],
        :expected_tags => [:b]}
        ]) do 

        date_between '2012-01-01', '2013-01-01' do
          set_tag :found
        end 
        
      end 
    end 


    it 'should handle amount matches' do

      assert_tags_are_assigned(
        [{date: '2012-02-01', 
        amount: "-275.00",
        description: "CHECK 9998",
         expected_tags: [:rent]},
        {date: '2012-02-03', 
        amount: -125.00,
        description: "CHECK 9999",
         expected_tags: [:utilities]}
        ]) do 

        amount -275.00 do
          tag :rent
        end
        amount -125.00 do
          tag :utilities
        end 
      end 
    end 


  it 'should handle nested queries' do

      assert_tags_are_assigned(
        [{date: '2012-02-01', 
        amount: "-275.00",
        description: "CHECK 9998",
         expected_tags: [:rent]},
        {date: '2012-02-03', 
        amount: "-125.00",
        description: "CHECK 9999",
         expected_tags: [:utilities]}
        ]) do 

        match "^CHECK " do  
          amount -275.00 do
            tag :rent
          end
          amount -125.00 do
            tag :utilities
          end 
        end 
        
      end 
    end 


    it 'should handle nested rules' do

      assert_tags_are_assigned(
        [{date: '2012-02-01', 
        amount: "-275.00",
        description: "CHECK 9998",
         expected_tags: [:expense,:rent]},
        {date: '2012-02-03', 
        amount: "-125.00",
        description: "CHECK 9999",
         expected_tags: [:expense,:utilities]}
        ]) do 

        tag :expense do 
          match "^CHECK " do
            after '2011-05-05' do
              amount -275.00 do
                tag :rent
              end
              amount -125.00 do
                tag :utilities
              end 
            end 
          end 
        end 
      end 
    end 

  end
end