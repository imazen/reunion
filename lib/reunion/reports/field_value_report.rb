 module Reunion
   class FieldValueReport < Report
    def initialize(slug, field)
      super(slug)
      @include_nil = true
      @include_all = true
      @field = field
      @nil_slug = :'[uncategorized]'
      @group_only = true
    end 
    attr_accessor :field, :include_nil, :nil_slug, :include_all, :export_all

    def get_child_reports(datasource)
      data = datasource.filter(&filter) if filter

      field_values = data.results.uniq{|t| t[field]}.map{|t| t[field]}
      field_values << :all if include_all 
      reports = []

      field_values.each do |val|
        next if val.nil? && !include_nil
        reports << Report.new(val.nil? ? nil_slug : val.to_sym, 
          filter: ->(t){ t[field] == val || val == :all}, 
          subreports: subreports.dup, 
          options: {omit_export: val == :all})
      end 
      reports
    end

  end
end