require 'minitest/autorun'
require 'reunion'
module Reunion

  describe 'StandardRuleSyntaxStuff' do

    before do
      schema = Schema.new(
                 {date: DateField.new(readonly: true, critical:true), 
                 amount: AmountField.new(readonly: true, critical:true),
                 tags: TagsField.new,
                 vendor: SymbolField.new,
                 vendor_tags: TagsField.new,
                 vendor_description: DescriptionField.new})

      @s = RuleSyntaxDefinition.new(schema)
      @s.add_query_methods
      @s.add_action_methods
      @methods = @s.compute_lookup_table
    end 

    it 'should have date query methods' do
      date_fields = [:for_date, :for_date_year, :date_after, :date_before]
      assert_equal [], (date_fields - @methods.keys),  "Missing methods"
    end 

    it 'should have vendor set methods' do
      date_fields = [:set_vendor, :set_vendor_description, :set_vendor_tag]
      assert_equal [], (date_fields - @methods.keys),  "Missing methods"
    end 


  end



end
