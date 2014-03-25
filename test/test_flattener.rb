require 'minitest/autorun'
require 'reunion'

module Minitest::Assertions
  def assert_str_eqal(a,b, message = nil)
    assert_equal a.inspect, b.inspect, message
  end
end 



module Reunion
  module Re
    describe ConditionFlattener do


      it 'should flatten a NOT expression' do
        e = Not.new(Cond.new)
        assert_str_eqal [[Cond.new(not:true)]],  ConditionFlattener.new.condition_tree_to_array_of_arrays(e)
      end


      it 'should flatten an OR expression' do
        e = Or.new([Cond.new(key:1),Cond.new(key:2)])
        assert_str_eqal [[Cond.new(key:1)],[Cond.new(key:2)]],  ConditionFlattener.new.condition_tree_to_array_of_arrays(e)
      end

      it 'should flatten an AND expression' do
        e = And.new([Cond.new(key:1),Cond.new(key:2)])
        assert_str_eqal [[Cond.new(key:1), Cond.new(key:2)]],  ConditionFlattener.new.condition_tree_to_array_of_arrays(e)
      end

      it 'should flatten an AND(OR, AND(OR)) expression' do
        e = And.new([Or.new([Cond.new(key:1)]), And.new([Or.new([Cond.new(key:2),Cond.new(key:3)]), Cond.new(key:4)])])
        expected = [[Cond.new(key:1), Cond.new(key:2),Cond.new(key:4)],[Cond.new(key:1), Cond.new(key:3),Cond.new(key:4)]]
        assert_str_eqal expected,  ConditionFlattener.new.condition_tree_to_array_of_arrays(e)
      end

      it 'should flatten nested ANDs' do
        e = And.new([And.new([Cond.new(key:1),Cond.new(key:2)]), Cond.new(key:3)])
        expected =  And.new([Cond.new(key:1),Cond.new(key:2), Cond.new(key:3)])
        assert_str_eqal expected, ConditionFlattener.new.flatten(And, e)
      end

      it 'should flatten nested ORs' do
        e = Or.new([Or.new([Cond.new(key:1),Cond.new(key:2)]), Cond.new(key:3)])
        expected =  Or.new([Cond.new(key:1),Cond.new(key:2), Cond.new(key:3)])
        assert_str_eqal expected, ConditionFlattener.new.flatten(Or, e)
      end

      it 'should permute properly' do
        e = [Or.new([Cond.new(key:1),Cond.new(key:2)]),Cond.new(key:3)]
        expected = [[Cond.new(key:1), Cond.new(key:3)],[Cond.new(key:2), Cond.new(key:3)]]
        assert_str_eqal expected, ConditionFlattener.new.permute_ors(e)
      end
      

      it 'should flatten rules into conditions' do 

        schema = Reunion::TransactionSchema.new
        rules = Reunion::Rules.new(Reunion::StandardRuleSyntax.new(schema))

        rules.add do
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

        conditions = rules.rules.map{|r| Reunion::Rule.new(r).condition}

        expected = [[Cond.new(key: :'description.downcase', comparator: :prefix, value: "check"),
                      Cond.new(key: :'date.mjd', comparator: :gt, value: 55686), 
                      Cond.new(key: :amount, comparator: :eq, value: BigDecimal.new(-275))]]

        assert_str_eqal expected, ConditionFlattener.new.condition_tree_to_array_of_arrays(conditions.first)

        expected = [[Cond.new(key: :'description.downcase', comparator: :prefix, value: "check"),
                      Cond.new(key: :'date.mjd', comparator: :gt, value: 55686), 
                      Cond.new(key: :amount, comparator: :eq, value: BigDecimal.new(-125))]]
        assert_str_eqal expected, ConditionFlattener.new.condition_tree_to_array_of_arrays(conditions.last)

      end 
    end

  end
end


