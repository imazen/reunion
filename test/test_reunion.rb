require 'minitest/autorun'
require 'reunion'
require_relative 'test_vendors'

module Reunion

  describe 'rule DSL' do

    before do
      @schema = TransactionSchema.new
      syntax = StandardRuleSyntax.new(@schema)
      @rules = Rules.new(syntax)
    end

    describe 'mixed block and chained rules' do
      it 'should produce rules of the correct chain length' do
        @rules.add do 
          tags :tag_one do
            tag :action_one
            tags(:tag_two).tags(:tag_three).tag :action_two
            tags(:tag_two).tag :action_three
          end 
        end 

        assert_equal [2,4,3], @rules.rules.map{|a|a.count}
      end 
    end 

    it 'should produce a valid decision tree' do 
      r = @rules
      r.match("^PREFIX ").tag(:found)
      eng = RuleEngine.new(r)
      expected =Re::DecisionTreeBuilder::DecisionNode.new()
      last = Re::DecisionTreeBuilder::DecisionNode.new(expected)
      expected.children << last
      expected.comparator = :yes
      last.comparator = :prefix
      last.value = "prefix"
      last.key = "description.downcase"
      last.results << [:something]
      assert_equal expected.inspect, eng.tree.inspect
    end 

    it 'should prep transaction descriptions properly' do
      @rules.match("^PREFIX ").tag(:found)
      eng = RuleEngine.new(@rules)
      txns = [Transaction.new(schema: @schema,:description => "PREFIX suffix")]
      assert_equal "PREFIX suffix".downcase, eng.prep_transactions(txns).first[:'description.downcase']
    end 
    it 'should evaluate prefix matches' do
      r = @rules
      r.match("^PREFIX ").tag(:found)
      txns = [Transaction.new(schema: @schema,:description => "PREFIX suffix")]
      RuleEngine.new(r).run(txns)
      assert_equal [:found], txns.first.tags
    end 

    it 'should evaluate exact matches' do
      r = @rules
      r.match("EXACT").tag(:found)
      txns = [Transaction.new(schema: @schema,:description => "EXACT")]
      RuleEngine.new(r).run(txns)
      assert_equal [:found], txns.first.tags
    end 

    it 'should evaluate case insensitive' do
      r = @rules
      r.match("EXACT").tag(:found)
      txns = [Transaction.new(schema: @schema,  :description => "EXaCT")]
      RuleEngine.new(r).run(txns)
      assert_equal [:found], txns.first.tags
    end 

    it 'should evaluate regexen' do
      r = @rules
      r.match([/exa?c?t?/i, /ex/i]).tag(:found)
      txns = [Transaction.new(schema: @schema, :description => "EXaCT")]
      RuleEngine.new(r).run(txns)
      assert_equal [:found], txns.first.tags
    end 

  end
=begin
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

    it 'should evaluate lambdas' do
      assert Rule.new([]).is_match [->(t){t.start_with?("E")}], ["EXACT"], nil
    end 
  end 
=end 

  describe 'default vendors' do
    it 'should parse' do 

      v = Vendors.new(StandardRuleSyntax.new(TransactionSchema.new))
      v.add_default_vendors
      re = RuleEngine.new(v)
    end 
  end 
  describe 'rule evaluation engine' do
    
    it 'should work' do

      schema = TransactionSchema.new
      syntax = StandardRuleSyntax.new(schema)
      r = Rules.new(syntax)

      r.add do
        for_tags(:b).set_tag :c
        for_tags(:a).set_tag :b
      end 



      txns = []
      txns << Transaction.new(schema: schema, :date => Date.parse('2014-01-01'), 
                                :amount => BigDecimal.new("20.00"),
                                :description => "Something",
                                :tags => [:a])
      re = RuleEngine.new(r)
      re.run(txns)
      
      assert_equal [:a,:b,:c], txns.first.tags
    end 
  end
end