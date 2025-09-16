module Reunion
  
  class ReportResult
    attr_accessor :title, :slugs, :schema, :options, :group_only, :summary_table, :name, :path, :breadcrumbs, :nav_label, :navs, :transactions, :calculations, :standard_calculations, :subreports
  end

  class ReportExporter
    def export(result, rootdir)
      return if result.options[:omit_export]

      pathbase = File.join(rootdir, *result.slugs.map{|v| v.to_s})
      if result.transactions
        Export.new.write_file("#{pathbase}.txt",Export.new.transactions_to_tsv(result.transactions))
      end

      if result.calculations.length > 0 || result.transactions.nil?
        rows = result.summary_table[:rows].map do |row|
          newrow = row.dup
          newrow[0] = newrow[0].map{|v| v[:name]} * "/"
          newrow
        end

        tsv = Export.new.pretty_tsv_from_arrays(result.summary_table[:headers],rows )
        Export.new.write_file("#{pathbase}_summary.txt",tsv)
        #export summary
      end

      result.subreports.each do |sr|
        export(sr, rootdir)
      end
    end 



    def export_csv(report:, schema:, txn_fields: )
      if report.transactions.nil?
        rows = report.summary_table[:rows].map do |row|
          newrow = row.dup
          newrow[0] = newrow[0].map{|v| v[:name]} * "/"
          newrow
        end
        Export.new.csv_from_arrays(report.summary_table[:headers],rows)
      else 
        Export.new.transactions_to_csv_allow_fields(report.transactions, txn_fields)
      end 
    end 

    def export_tsv(report:, schema:, txn_fields: )
      if report.transactions.nil?
        rows = report.summary_table[:rows].map do |row|
          newrow = row.dup
          newrow[0] = newrow[0].map{|v| v[:name]} * "/"
          newrow
        end
        Export.new.tsv_from_arrays(report.summary_table[:headers],rows)
      else 
        Export.new.transactions_to_tsv_allow_fields(report.transactions, txn_fields)
      end 
    end 
  end

  class ReportGenerator
    def generate(slugs: , reports: , datasource: , is_root: true, **options)
      slugs = slugs.map{|s| s.to_s.downcase.to_sym}
      result = ReportResult.new
      result.breadcrumbs = []

      child_reports = reports
      child_data = datasource
      report = nil

      slugs.each_with_index do |name, ix|
        report = child_reports.find{|r| r.slug == name}
        result.name = name
        path = slugs[0..ix]
        result.slugs = path
        result.path = path.join('/')
        raise "Failed to find report (#{path.join('/')}) during generation of (#{slugs.join('/')}) within set [#{child_reports.map{|r|r.slug}.join(',')}], datasource results #{child_data.results.count}\n" if report.nil?
        child_data = child_data.unfilter unless report.inherit_filters
        child_data = child_data.filter(&(report.filter)) if report.filter
        result.breadcrumbs << {name: name.to_s, path: path.join('/')}
        child_reports = report.get_child_reports(child_data)
      end

      #STDERR << "Filtered to #{child_data.results.count}"
      result.standard_calculations = report.calculate_per_currency(report.standard_calculations, child_data)
      result.calculations = report.calculate_per_currency(report.calculations, child_data)
      result.options = opts = report.report_options
      result.group_only = report.group_only
      unless report.group_only
        result.transactions = child_data.results
        sort_field = opts[:sort_by]
        result.transactions = result.transactions.sort_by do |t|
          str = "#{t.date_str}|#{t.description.strip.squeeze(' ').downcase}|#{t.date_str}|#{'%.2f' % t.amount}|#{t.account_sym}"
          sort_field && t[sort_field] ? [t[sort_field],str] : [:empty, str]
        end
        result.transactions = result.transactions.reverse if opts[:sort_order] == :reverse
      end
      result.title = report.title
      result.schema = datasource.schema
      result.subreports = child_reports.map{|r|
        generate(slugs: slugs + [r.slug], reports: reports, datasource: datasource, is_root: false, **options)
      }
      result.navs = result.subreports.map{|r| [r.name, r.path]}
      result.summary_table = generate_summary_table(result, is_root, **options)
      result
    end

    def generate_summary_table(result, is_root, simplified_totals: false)
      cols = ["Name", "Currency", "Value", "Debits", "Credits", "30d Avg"]

      rows = []
      rows.concat(result.calculations.map{|c| 
        useful = c[:value] && (!c[:txn_count] || c[:txn_count] > 0)
        useful ? [result.breadcrumbs + [{name: c[:label].to_s}],  c[:currency], c[:value]] : nil
      }.compact)

      #STDERR << "#{result.path} group_only=#{result.group_only}\n"
      unless result.group_only
        currencies = result.standard_calculations.map{|h| h[:currency]}.uniq
        currencies.each do |currency|
          in_currency = result.standard_calculations.select{|v| v[:currency] == currency}
          net = in_currency.find{|v| v[:slug] == :net}
          debit = in_currency.find{|v| v[:slug] == :debit}
          credit = in_currency.find{|v| v[:slug] == :credit}
          avg = in_currency.find{|v| v[:slug] == :avg30}
          next unless [net,debit,credit,avg].any?{|v| v && v[:txn_count] > 0}
          values = [net, debit, credit].map{|v|
            if simplified_totals
              v ? "#{v[:value]}" : nil 
            else
              v ? "#{v[:value]} (#{v[:txn_count]})" : nil
            end 
          }
          values << (avg ? avg[:value] : nil) unless simplified_totals
          rows << [result.breadcrumbs, currency] + values
        end
      end


      result.subreports.each do |sr|
        rows.concat(sr.summary_table[:rows])
      end

      rows.each do |row|
        row[0] = row[0][result.slugs.count..-1]
      end if is_root

      {headers: cols, rows: rows}
    end


  end

end