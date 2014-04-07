module Reunion

  class ReportDataSource
    attr_accessor :all_transactions, :results, :schema, :applied

    def initialize(all_transactions, results, schema)
      @all_transactions = all_transactions
      @results = results
      @schema = schema
      @applied = []
    end

    def get_cached_result(filters)
      return unfilter if filters.empty?
      key = [all_transactions.object_id, filters]
      @@cache ||= {}
      result = @@cache[key]
      unless result
        result = get_cached_result(filters[0..-2])
        result = ReportDataSource.new(all_transactions,result.results.select(&(filters.last)), schema)
        result.applied = filters
        @@cache[key] = result
      end
      result
    end 

    def filter(&filter)
      get_cached_result(applied + [filter])
    end

    def filter_currency(currency)
      @@currency_lambdas ||= {}
      @@currency_lambdas[currency] ||= ->(t){t[:currency] == currency}
      filter(&(@@currency_lambdas[currency]))
    end

    def all_currencies
      @@cache ||= {}
      key = [all_transactions.object_id,:currencies]
      @@cache[key] ||= all_transactions.uniq{|t| t[:currency]}.map{|t| t[:currency]}.sort.reverse
    end

    def unfilter
      ReportDataSource.new(all_transactions,all_transactions, schema)
    end
  end
end
