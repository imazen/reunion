 module Reunion
   class FieldValueReport < Report
    def initialize(slug, field)
      super(slug)
      @include_nil = true
      @include_all = true
      @field = field
      @nil_slug = :nil
    end 
    attr_accessor :field, :include_nil, :nil_slug, :include_all, :export_all

    def get_child_reports(datasource)
      data = datasource.filter(&filter) if filter

      field_values = data.results.map{|t| t[field]}.uniq
      field_values << :all if include_all 
      reports = []

      field_values.each do |val|
        next if val.nil? && !include_nil
        reports << Report.new(val.nil? ? nil_slug : val.to_sym, 
          filter: ->(t){ t[field] == val || val == :all}, 
          subreports: subreports.dup,
          report_options: report_options.dup)
      end 
      reports
    end

  end
end