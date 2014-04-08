module Reunion
  class ByYearReport < Report

    def initialze(slug)
      super(slug)
      @group_only = true
    end 

    def get_child_reports(datasource)
      data = datasource.filter(&filter) if filter

      years = data.results.uniq{|t| t.date.year}.map{|t| t.date.year}.compact
      years.unshift(:all_years)
      years.map do |val|
        Report.new(val.to_s.to_sym, 
          filter: ->(t){ t.date.year == val || val == :all_years}, 
          subreports: subreports.dup,
          group_only: subreports.count > 0,
          options: {omit_export: val == :all_years})
      end 

    end 

  end
end