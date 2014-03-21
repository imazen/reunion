require 'minitest/autorun'
require 'reunion'
module Reunion
  module Re
    describe ConditionFlattener do


      it 'should flatten a NOT expression' do
        e = Not.new(Cond.new)
        assert_equal [[Cond.new(not:true)]],  ConditionFlattener.new.condition_tree_to_array_of_arrays(e)
      end


      it 'should flatten an OR expression' do
        e = Or.new([Cond.new(key:1),Cond.new(key:2)])
        assert_equal [[Cond.new(key:1)],[Cond.new(key:2)]],  ConditionFlattener.new.condition_tree_to_array_of_arrays(e)
      end

      it 'should flatten an AND expression' do
        e = And.new([Cond.new(key:1),Cond.new(key:2)])
        assert_equal [[Cond.new(key:1), Cond.new(key:2)]],  ConditionFlattener.new.condition_tree_to_array_of_arrays(e)
      end

      it 'should flatten an AND(OR, AND(OR)) expression' do
        e = And.new([Or.new([Cond.new(key:1)]), And.new([Or.new([Cond.new(key:2),Cond.new(key:3)]), Cond.new(key:4)])])
        expected = [[Cond.new(key:1), Cond.new(key:2),Cond.new(key:4)],[Cond.new(key:1), Cond.new(key:3),Cond.new(key:4)]]
        assert_equal expected,  ConditionFlattener.new.condition_tree_to_array_of_arrays(e)
      end

      it 'should flatten nested ANDs' do
        e = And.new([And.new([Cond.new(key:1),Cond.new(key:2)]), Cond.new(key:3)])
        expected =  And.new([Cond.new(key:1),Cond.new(key:2), Cond.new(key:3)])
        assert_equal expected, ConditionFlattener.new.flatten(And, e)
      end

      it 'should flatten nested ORs' do
        e = Or.new([Or.new([Cond.new(key:1),Cond.new(key:2)]), Cond.new(key:3)])
        expected =  Or.new([Cond.new(key:1),Cond.new(key:2), Cond.new(key:3)])
        assert_equal expected, ConditionFlattener.new.flatten(Or, e)
      end

      it 'should permute properly' do
        e = [Or.new([Cond.new(key:1),Cond.new(key:2)]),Cond.new(key:3)]
        expected = [[Cond.new(key:1), Cond.new(key:3)],[Cond.new(key:2), Cond.new(key:3)]]
        assert_equal expected, ConditionFlattener.new.permute_ors(e)
      end
      
    end
  end
end


