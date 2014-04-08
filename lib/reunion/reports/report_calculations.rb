module Reunion
  
  class ReportValue
    attr_accessor :slug, :label, :value, :currency, :calculator, :filter, :inherit_filters
    def initialize(slug, label, value=nil, currency=nil, calculator: nil, filter: nil, inherit_filters: true)
      @slug = slug
      @label = label
      @value = value
      @currency = currency
      @calculator = calculator
      @inherit_filters = inherit_filters
      @filter = filter
    end
  end

  class ReportValueTxnCount < ReportValue
    def initialize(slug, label,filter: nil, inherit_filters: true)
      @slug = slug
      @label = label
      @filter = filter
      @calculator = ->(txns){txns.count}
      @inherit_filters = inherit_filters
    end
  end

  class ReportValueSum < ReportValue
    def initialize(slug, label,filter: nil, inherit_filters: true)
      @slug = slug
      @label = label
      @filter = filter
      @calculator = ->(txns){ReportValueSum.sum_amounts(txns).to_cur}
      @inherit_filters = inherit_filters
    end

    def self.sum_amounts(txns, &filter)
      amount = 0
      txns.each do |t| 
        amount += t.amount if !filter || filter.call(t)
      end
      amount
    end
  end 
  class ReportValueDurationAvg < ReportValue
    def initialize(slug, label,days: 30, filter: nil, inherit_filters: true)
      @slug = slug
      @label = label
      @filter = filter
      @inherit_filters = inherit_filters
      @calculator = ->(txns){
        return nil if txns.count < 2
        duration = txns.max{|t| t.date}.date - txns.min{|t| t.date}.date
        return nil if duration < days

        factor = days.to_f / duration.to_f  

        sum = ReportValueSum.sum_amounts(txns) * factor
        debits = ReportValueSum.sum_amounts(txns){|t| t.amount > 0} * factor
        credits = ReportValueSum.sum_amounts(txns){|t| t.amount < 0} * factor
        "#{sum.to_cur} (#{debits.to_cur} #{credits < 0 ? '' : '+'} #{credits.to_cur.gsub(/\-/,'- ')})"
      }
    end
  end
end