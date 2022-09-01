require 'minitest/autorun'
require 'reunion'
module Reunion

  describe SymbolField do

    before do
      @f = SymbolField.new
      
    end 

    it 'should normalize strings properly' do
      assert_equal :some_stuff, @f.normalize("  soMe  stuff ")
    end 

    it 'should normalize symbols properly' do
      assert_equal :some_stuff, @f.normalize(:" soMe stuff")
    end 

  end

  describe AmountField do
    before do
      @f = AmountField.new(default_value: 0)
    end

    it 'should normalize amounts properly' do
      assert_equal 139.12, @f.normalize("139.12")
    end 
  end 

  describe 'TransactionSchema' do
    before do
      @schema = TransactionSchema.new
      @txns = [Transaction.new(schema: @schema, from_hash: {date: '2013-01-1', amount: "-134.22", description: " some    stuff "})]
    end

    it 'should normalize a transaction fully' do
      normalized = @schema.normalize(@txns.first)

      assert_equal Date.parse('2013-01-01'), normalized.date
      assert_equal(-134.22, normalized.amount)
      assert_equal "some stuff", normalized.description
    end 
  end

  describe DateField do
    before do
      @f = DateField.new
      @compare = @f.query_methods.find{|q| q.name == :compare}
      @year = @f.query_methods.find{|q| q.name == :year}
      @after = @f.query_methods.find{|q| q.name == :after}
      @before = @f.query_methods.find{|q| q.name == :before}
      @between = @f.query_methods.find{|q| q.name == :between}
    end

 


    it 'should generate 5 methods' do
      assert_equal [:year, :before, :after, :between, :compare].sort, @f.query_methods.map{|q| q.name}.sort
    end
  end

end
