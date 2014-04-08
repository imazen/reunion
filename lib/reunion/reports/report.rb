module Reunion
  

  class Report
    def initialize(slug, title: slug, filter: ->(t){true}, subreports: [], 
      calculations: [], group_only: false, options: {})
      @slug = slug
      @title = title || slug.to_s.gsub("_\-", " ").capitalize
      @filter = filter
      @calculations = calculations + subreports.select{|r| r.is_a?(ReportValue)}
      @subreports = subreports.reject{|r| r.is_a?(ReportValue)}
      @report_options = options
      @group_only = group_only
      @inherit_filters = true
    end

    attr_accessor :slug, :title, :filter, :subreports, :calculations, :inherit_filters, :group_only, :report_options
 
    def get_child_reports(datasource)
      @subreports
    end

    def standard_calculations
      #persistent lambda objects allows result caching within datasource
      @@debit_lambda ||= ->(t){t.amount < 0} 
      @@credit_lambda ||= ->(t){t.amount > 0}
      a = []
      a << ReportValueSum.new(:net, "Net")
      a << ReportValueDurationAvg.new(:avg30, "30d Avg")
      a << ReportValueSum.new(:debit, "Debits", filter: @@debit_lambda) 
      a << ReportValueSum.new(:credit, "Credits", filter: @@credit_lambda)
      @@standard_calculations ||= a
    end 

    def calculate_per_currency(calculations, datasource)
      datasource = datasource.filter(&filter) if @filter
      results = []
      calculations.each do |c|
        results.concat(datasource.all_currencies.map{ |currency|
          if c.currency && c.value
            c.currency == currency ?  {currency: currency, slug: c.slug, label: c.label,value: c.value} : nil
          elsif c.calculator
            data = c.inherit_filters ? datasource : datasource.unfilter
            data = data.filter(&(c.filter)) if c.filter
            txns = data.filter_currency(currency).results
            {currency: currency, slug: c.slug, label: c.label,value: c.calculator.call(txns), txn_count: txns.count}
          else
            raise "Calcuations must have a lambda or a value. #{c.inspect}"
          end 
        }.compact)
      end
      results 
    end

  end

end