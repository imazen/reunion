module Reunion
  class ByYearReport < Report

    def initialze(slug, omit_export: false)
      super(slug, omit_export: omit_export)
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
          calculations: calculations.dup,
          group_only: subreports.count > 0,
          omit_export: skip_export || val == :all_years)
      end 

    end 

  end

  class QuarterlyReport < Report

    def initialze(slug, omit_export: false)
      super(slug, omit_export: omit_export)
      @group_only = true
    end 

    def get_child_reports(datasource)
      data = datasource.filter(&filter) if filter

      years = data.results.uniq{|t| t.date.year}.map{|t| t.date.year}.compact
      years.map do |year|
        s = []
        (1..4).each do |quarter|
          startmonth = 1 + (quarter - 1) * 3
          endmonth = startmonth + 2
          s << Report.new("q#{quarter}".to_sym,
            filter: ->(t){t.date.month.between?(startmonth,endmonth)},
            subreports: subreports.dup,
            calculations: calculations.dup,
            omit_export: skip_export,
            group_only: true)
        end

        Report.new(year.to_s.to_sym, 
          filter: ->(t){ t.date.year == year}, 
          subreports: s,
          omit_export: skip_export,
          group_only: true)
      end
    end 

  end

end