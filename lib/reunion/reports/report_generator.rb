module Reunion
  
  class ReportResult
    attr_accessor :title, :schema, :options, :summary_table, :name, :path, :breadcrumbs, :nav_label, :navs, :transactions, :calculations, :standard_calculations, :subreports
  end


  class ReportGenerator

    def generate(slugs, reports, datasource)
      slugs = slugs.map{|s| s.to_s.downcase.to_sym}
      result = ReportResult.new
      result.breadcrumbs = []

      child_reports = reports
      child_data = datasource.dup
      report = nil

      slugs.each_with_index do |name, ix|
        report = child_reports.find{|r| r.slug == name}
        result.name = name
        path = slugs[0..ix]
        result.path = path.join('/')
        raise "Failed to find report (#{path.join('/')}) during generation of (#{slugs.join('/')}) within set [#{child_reports.map{|r|r.slug}.join(',')}]\n" if report.nil?
        child_data = child_data.unfilter unless report.inherit_filters
        child_data = child_data.filter(&(report.filter)) if report.filter
        result.breadcrumbs << {name: name.to_s, path: path.join('/')}
        child_reports = report.get_child_reports(child_data)
      end

      #STDERR << "Filtered to #{child_data.results.count}"
      result.standard_calculations = report.calculate_per_currency(report.standard_calculations, child_data)
      result.calculations = report.calculate_per_currency(report.calculations, child_data)
      result.options = opts = report.report_options
      result.transactions = opts[:hide_transactions] ? [] : child_data.results
      result.transactions = result.transactions.sort_by{|t| t[opts[:sort_by]]} if opts[:sort_by]
      result.transactions = result.transactions.reverse if opts[:sort_order] == :reverse
      result.title = report.title
      result.schema = datasource.schema
      result.subreports = child_reports.map{|r|
        generate(slugs + [r.slug], reports, child_data)
      }
      result.summary_table = generate_summary_table(result)
      result
    end

    def generate_summary_table(result)
      cols = ["Name", "Currency", "Value", "Debits", "Credits", "30d Avg"]

      rows = []
      rows.concat(result.calculations.map{|c| 
        useful = c[:value] && (!c[:txn_count] || c[:txn_count] > 0)
        useful ? [result.breadcrumbs + [{name: c[:label].to_s}],  c[:currency], c[:value]] : nil
      }.compact)

      unless result.options[:hide_standard_calculations]
        currencies = result.standard_calculations.map{|h| h[:currency]}.uniq
        currencies.each do |currency|
          in_currency = result.standard_calculations.select{|v| v[:currency] == currency}
          net = in_currency.find{|v| v[:slug] == :net}
          debit = in_currency.find{|v| v[:slug] == :debit}
          credit = in_currency.find{|v| v[:slug] == :credit}
          avg = in_currency.find{|v| v[:slug] == :avg30}
          next unless [net,debit,credit,avg].any?{|v| v && v[:txn_count] > 0}
          values = [net, debit, credit].map{|v|
            v ? "#{v[:value]} (#{v[:txn_count]})" : nil
          }
          values << (avg ? avg[:value] : nil)
          rows << [result.breadcrumbs, currency] + values
        end
      end


      result.subreports.each do |sr|
        rows.concat(sr.summary_table[:rows])
      end

      {headers: cols, rows: rows}
    end


  end

end