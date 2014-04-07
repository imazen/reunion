module Reunion
  

 
  ReportOptions = Struct.new(:sort_by, :sort_order, :hide_transactions, :hide_subreport_summaries)


  class Report
    def initialize(slug, title: slug, filter: ->(t){true}, subreports: [], calculations: [], options: ReportOptions.new)
      @slug = slug
      @title = title || slug.to_s.gsub("_\-", " ").capitalize
      @filter = filter
      @calculations = calculations + subreports.select{|r| r.is_a?(ReportValue)}
      @subreports = subreports.reject{|r| r.is_a?(ReportValue)}
      @report_options = options
      @inherit_filters = true
    end

    attr_accessor :slug, :title, :filter, :subreports, :calculations, :inherit_filters, :report_options
 
    def get_child_reports(datasource)
      @subreports
    end

    def standard_calculations
      @@debit_lambda ||= ->(t){t.amount < 0}
      @@credit_lambda ||= ->(t){t.amount > 0}
      a = []
      a << ReportValueTxnCount.new("TxnCt")
      a << ReportValueSum.new("Net")
      a << ReportValueDurationAvg.new("30d Net Avg")
      a << ReportValueTxnCount.new("Debit Ct", filter: @@debit_lambda)
      a << ReportValueSum.new("Debits", filter: @@debit_lambda) 
      a << ReportValueTxnCount.new("Credits Ct", filter: @@credit_lambda)
      a << ReportValueSum.new("Credits", filter: @@credit_lambda)
      @@standard_calculations ||= a
    end 

    def get_calculations_by_currency(datasource)
      calculations = @calculations + standard_calculations
      datasource = datasource.filter(&filter) if @filter
      Hash[datasource.all_currencies.map{ |currency|
        calcs = Hash[calculations.map do |c|
          if c.currency && c.value
            c.currency == currency ? [c.label,c.value] : nil
          else
            data = c.inherit_filters ? datasource : datasource.unfilter
            data = data.filter(&(c.filter)) if c.filter
            txns = data.filter_currency(currency).results
            [c.label, c.calculator.call(txns)]
          end 
        end.compact]
        [currency, calcs]
      }]
    end 

  end

end