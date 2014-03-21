require 'minitest/autorun'
require 'reunion'
module Reunion

  describe OverrideSet do

    before do
     
      @txns = []
      @txns << Transaction.new({:date => Date.parse('2014-01-01'), 
                                :amount => BigDecimal.new("20.00"),
                                :description => "Something",
                                :tags => [:a], 
                                :account_sym => :bank})

      @set = OverrideSet.new
      OverrideSet.set_subindexes(@txns)
      @set.set_override(@txns[0], {tags: [:b]})
    end 

    it 'should apply overrides correctly' do
      @set.apply_all(@txns)
      assert_equal [:b], @txns[0].tags
    end 

    it 'should round-trip the representation' do
      serialized = @set.to_tsv_str 
      deserialized = OverrideSet.from_tsv_str(serialized)
      assert_equal @set.overrides, deserialized.overrides
    end 
  end
end
