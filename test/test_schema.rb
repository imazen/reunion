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
