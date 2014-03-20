require 'minitest/autorun'
require 'reunion'
module Reunion

  describe SymbolField do

    before do
      @f = SymbolField.new
      @compare = @f.query_methods.first.lambda_generator
    end 

    it 'should normalize strings properly' do
      assert_equal :some_stuff, @f.normalize("  soMe  stuff ")
    end 

    it 'should normalize symbols properly' do
      assert_equal :some_stuff, @f.normalize(:" soMe stuff")
    end 

    it 'should generate working query methods' do
      assert @compare.call([[:a, :b]]).call(:a)
      assert !@compare.call([:c, :b]).call(:a)
      assert @compare.call([:a, :b]).call(:a)
      assert @compare.call([:a]).call(:a)
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

    it 'should support year comparison' do
      assert @year.lambda_generator.call([2012]).call(@f.normalize('2012-05-02'))
      assert @year.lambda_generator.call(['2012']).call(@f.normalize('2012-05-02'))
      assert !@year.lambda_generator.call(['2013']).call(@f.normalize('2012-05-02'))
    end



    it 'should generate 5 methods' do
      assert_equal [:year, :before, :after, :between, :compare].sort, @f.query_methods.map{|q| q.name}.sort
    end
  end

end
