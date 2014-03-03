require 'minitest/autorun'
require 'reunion'
module Reunion

  describe 'rule DSL' do

    describe 'mixed block and chained rules' do
      it 'should produce rules of the correct chain length' do
        r = Rules.new

        r.add do 
          tags :tag_one do
            tag :action_one
            tags(:tag_two).tags(:tag_three).tag :action_two
            tags(:tag_two).tag :action_three
          end 
        end 

        assert_equal [2,4,3], r.rules.map{|a|a.count}
      end 
    end 
  end
  describe 'rule evaluation engine' do
    
    it 'should work' do


      r = Rules.new 

      r.add do
        for_tags(:b).set_tag :c
        for_tags(:a).set_tag :b
      end 



      v = Vendors.new
      v.add_default_vendors
      c = Clients.new

      txns = []
      txns << Transaction.new({:date => Date.parse('2014-01-01'), 
                                :amount => BigDecimal.new("20.00"),
                                :description => "Something",
                                :tags => [:a]})
      re = RuleEngine.new(r, v, c)
      re.run(txns)
      
      assert txns.first.tags.include? :b

      assert txns.first.tags.include? :c
    end 
  end
end