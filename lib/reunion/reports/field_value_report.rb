 module Reunion
   class FieldValueReport < Report
    def initialize(slug, field, permutations: [nil], omit_export: false)
      super(slug, omit_export: omit_export)
      @include_nil = true
      @include_all = true
      @field = field
      @nil_slug = :'[uncategorized]'
      @group_only = true
      @permutations = permutations
    end 
    attr_accessor :field, :include_nil, :nil_slug, :include_all, :export_all, :permutations

    def get_child_reports(datasource)
      data = datasource.filter(&filter) if filter

      field_values = data.results.uniq{|t| t[field]}.map{|t| t[field]}
      include_nil = @include_nil && field_values.include?(nil)
      field_values = field_values.compact.sort
      field_values << nil if include_nil
      field_values << :all if include_all 
      reports = []

      field_values.each do |val|
        next if val.nil? && !include_nil
        (permutations || [nil]).each do |permutation|
          slug = val.nil? ? nil_slug : val.to_sym
          lambda = ->(t){ t[field] == val || val == :all}
          #Modify slug and lambda for permuations
          slug = "#{slug.to_s}_#{permutation[:suffix].to_s}".to_sym if permutation && permutation[:suffix] 
          lambda = ->(t){ permutation[:lambda].call(t) && (t[field] == val || val == :all)} if permutation && permutation[:lambda] 
          reports << Report.new(slug, 
            filter: lambda, 
            subreports: subreports.dup, 
            omit_export: skip_export || val == :all)
        end 
      end 
      reports
    end

  end
end