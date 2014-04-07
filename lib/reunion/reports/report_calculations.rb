module Reunion
  
  class ReportValue
    attr_accessor :label, :value, :currency, :calculator, :filter, :inherit_filters
    def initialize(label, value=nil, currency=nil, calculator: nil, filter: nil)
      @label = label
      @value = value
      @currency = currency
      @calculator = calculator
      @inherit_filters = true
      @filter = filter
    end
  end

  class ReportValueTxnCount < ReportValue
    def initialize(label = "Txn Ct",filter: nil)
      @label = label
      @filter = filter
      @calculator = ->(txns){txns.count}
      @inherit_filters = true
    end
  end

  class ReportValueSum < ReportValue
    def initialize(label,filter: nil)
      @label = label || "Sum"
      @filter = filter
      @calculator = ->(txns){ReportValueSum.sum_amounts(txns).to_usd}
      @inherit_filters = true
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
    def initialize(label = "30d avg",days: 30, filter: nil)
      @label = label
      @filter = filter
      @inherit_filters = true
      @calculator = ->(txns){
        sum = ReportValueSum.sum_amounts(txns)
        return nil if txns.count < 2
        duration = txns.max{|t| t.date}.date - txns.min{|t| t.date}.date
        return nil if duration < days
        (days.to_f / duration.to_f * sum.to_f).to_usd
      }
    end
  end
end