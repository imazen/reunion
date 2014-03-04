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
    it 'should evaluate prefix matches' do
      r = Rules.new
      r.match("^PREFIX ").tag(:found)
      txns = [Transaction.new({:description => "PREFIX suffix"})]
      RuleEngine.new(r).run(txns)
      assert_equal [:found], txns.first.tags
    end 

    it 'should evaluate exact matches' do
      r = Rules.new
      r.match("EXACT").tag(:found)
      txns = [Transaction.new({:description => "EXACT"})]
      RuleEngine.new(r).run(txns)
      assert_equal [:found], txns.first.tags
    end 

    it 'should evaluate case insensitive' do
      r = Rules.new
      r.match("EXACT").tag(:found)
      txns = [Transaction.new({:description => "EXaCT"})]
      RuleEngine.new(r).run(txns)
      assert_equal [:found], txns.first.tags
    end 

    it 'should evaluate regexen' do
      r = Rules.new
      r.match([/exa?c?t?/i, /ex/i]).tag(:found)
      txns = [Transaction.new({:description => "EXaCT"})]
      RuleEngine.new(r).run(txns)
      assert_equal [:found], txns.first.tags
    end 

  end

  describe 'string match evaluator' do
    it 'should evaluate prefix matches' do
      assert Rule.new([]).is_match ["^PREFIX "], ["PREFIX suffix"], nil
    end 

    it 'should evaluate exact matches' do
      assert Rule.new([]).is_match ["EXACT"], ["EXACT"], nil
    end 

    it 'should evaluate case insensitive' do
      assert Rule.new([]).is_match ["EXaCT"], ["EXACT"], nil
    end 

    it 'should evaluate regexen' do
      assert Rule.new([]).is_match [/exa?c?t?/i], ["EXACT"], nil
    end 
    it 'should evaluate regexen arrays' do
      assert Rule.new([]).is_match [/^E/i,/exa?c?t?/i], ["EXACT"], nil
    end 
    it 'should evaluate regexen anchored' do
      assert Rule.new([]).is_match [/\Aexa?c?t?\Z/i], ["EXACT"], nil
    end 
  end 
  describe 'default vendors' do
    it 'should parse' do 
      v = Vendors.new
      v.add_default_vendors
      re = RuleEngine.new(v)
    end 
  end 
  describe 'rule evaluation engine' do
    
    it 'should work' do


      r = Rules.new 

      r.add do
        for_tags(:b).set_tag :c
        for_tags(:a).set_tag :b
      end 



      txns = []
      txns << Transaction.new({:date => Date.parse('2014-01-01'), 
                                :amount => BigDecimal.new("20.00"),
                                :description => "Something",
                                :tags => [:a]})
      re = RuleEngine.new(r)
      re.run(txns)
      
      assert_equal [:a,:b,:c], txns.first.tags
    end 
  end
end