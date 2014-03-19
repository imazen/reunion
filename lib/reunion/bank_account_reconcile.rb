
class Reunion::BankAccount

  def sort_to_reduce_discrepancies(startbal, combined)

    sorted = []
    #Group by day
    by_day = combined.compact.group_by{|r| r[:date].strftime("%Y-%m-%d")}.values

    balance = startbal || 0
    by_day.each do |day|
      day_start = balance
      daily_delta = 0

      index = 2
      wrapped = day.map do |row|
        #Calculate 'before' transaction balances
        w = {row: row}
     
        w[:amount] = row[:amount] || 0

        if row.key?(:balance_after)
          w[:daily_delta] = daily_delta = row[:balance_after] - day_start
        elsif w[:amount] != 0
          w[:daily_delta] = daily_delta += w[:amount]
        elsif row[:bal] && !row[:balance].nil?
          w[:daily_delta] = row[:balance] - day_start
        else
          w[:daily_delta] = daily_delta
        end
        w[:index] = index += 2
        w
      end

      txns = [{amount: 0, daily_delta:0, placeholder:true, index: 0}] + wrapped.select{ |b| b[:amount] != 0 }
      bals = wrapped.select{ |b| b[:amount] == 0 }
      bals.each do |b|
        closest = txns.map{ |t| { delta: (b[:daily_delta] - t[:daily_delta]).abs, txn: t}}.sort_by { |p| p[:delta]}
        b[:index] = closest.first[:txn][:index] + 1
      end

      results = (txns + bals).stable_sort_by{|e| e[:index]}

      balance += results.reverse.detect {|e| e[:daily_delta]}[:daily_delta]
      
      sorted << results.reject{|e|e[:placeholder]}.map{|e| e[:row]}
    
    end 

    sorted.flatten
  end

  def reconcile
    transactions = self.transactions
    statements = self.statements

    #input: transaction amounts, transaction after_balance values, transaction 
    # Establish knowns. 


    #Order statements first...
    combined = statements.map {|t| t[:bal] = true; t} + transactions

    combined = combined.compact.stable_sort_by { |t| t[:date].iso8601 }

    #Shuffle statements forward to minimize discrepancies
    combined = sort_to_reduce_discrepancies(0,combined)

    report = []
    # Output columns:
    # Date, Amount, Balance, Discrepancy, Description, Source

    last_balance_row = nil
    last_statement = nil
    balance = 0


    combined.each_with_index do | row, index |
      result_row = {}
      result_row[:id] = row[:id] if row[:id]
      result_row[:key] = row.lookup_key if row.respond_to? :lookup_key
      result_row[:date] = row[:date] if row[:date]
      result_row[:amount] = row[:amount] if row[:amount]
      result_row[:description] = row[:description] if row[:description]
      result_row[:source] = File.basename(row[:source].to_s) if row[:source]

      row_amount = row[:amount] ? row[:amount] : 0
      #What should the balance be after this row?
      balance_after = row[:bal] ? row[:balance] : (row.key?(:balance_after) ? row[:balance_after] : (balance + row_amount))
      #p row if balance_after == 0
      result_row[:balance] = balance_after

      discrepancy_amount = balance_after - (row_amount + balance)

      report << nil if row[:bal]

      if discrepancy_amount.abs > 0.001

        #Get the path of the file that provided the balance in the given row
        get_balance_source = lambda do |for_row|
          next for_row[:source] if for_row[:bal] || for_row[:source_rows].nil? || for_row[:balance_after].nil?
          next for_row[:source_rows].detect { |r| r[:balance_after] == for_row[:balance_after]}[:source]
        end

        source = ""

        if last_balance_row.nil?
          description = "Using starting balance of " + ("%.2f" % (balance + discrepancy_amount))
          source = "From #{File.basename(get_balance_source.call(row).to_s)}"
        else
          description = "Discrepancy between #{last_balance_row[:date].strftime("%Y-%m-%d")} and #{result_row[:date].strftime("%Y-%m-%d")} of " + "%.2f" % discrepancy_amount 
     
          last_balance_source = get_balance_source.call(last_balance_row)
          balance_source = get_balance_source.call(row)

          #p last_balance_row if last_balance_source.nil? 
          #p row if balance_source.nil? 

          if (last_balance_source == balance_source)
            source = "Discrepancy within file: #{File.basename(balance_source.to_s)}"
          else
            source = "Discrepancy between file #{File.basename(last_balance_source.to_s)} and #{File.basename(balance_source.to_s)}"
          end 

        end

        #We have a discrepancy
        report << {amount:discrepancy_amount, balance: balance, discrepancy: discrepancy_amount, description: description, source: source}
      end

      balance = balance_after

      report << result_row

      report << nil if row[:bal]

      last_balance_row = row if row[:bal] || row.key?(:balance_after)
      last_statement = row if row[:bal]

    end

    @final_discrepancy = report.compact.map { |r| r[:discrepancy]}.compact.inject(0, :+)
    @reconciliation_report = report
    report
  end 
  attr_accessor :reconciliation_report 
end
