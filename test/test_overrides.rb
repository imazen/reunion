require 'minitest/autorun'
require 'reunion'
module Reunion

  describe OverrideSet do

    before do

      @txns = []
      @txns << Transaction.new(from_hash: {:date => Date.parse('2014-01-01'),
                                :amount => BigDecimal("20.00"),
                                :description => "Something",
                                :tags => [:a],
                                :account_sym => :bank})
      @schema = Schema.new(date: DateField.new(readonly: true, critical: true),
                           amount: AmountField.new(readonly: true, critical: true, default_value: 0),
                           description: DescriptionField.new(readonly: true, default_value: ''),
                           tags: TagsField.new,
                           memo: DescriptionField.new,
                           account_sym: SymbolField.new(readonly: true))
      @set = OverrideSet.new(@schema)
      OverrideSet.set_subindexes(@txns)
      @set.set_override(@txns[0], {tags: [:b]})
    end

    it 'should apply overrides correctly' do
      @set.apply_all(@txns)
      assert_equal [:b], @txns[0].tags
    end

    it 'should round-trip the representation' do
      serialized = @set.to_tsv_str
      deserialized = OverrideSet.from_tsv_str(serialized, @schema)
      assert_equal @set.overrides, deserialized.overrides
    end
  end
end
