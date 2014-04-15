class Reunion::Export

  def transactions_to_tsv(txns)
    input_file_to_tsv(txns, drop_columns: [:subindex, :schema, :source, :priority])
  end

  def input_file_to_tsv(txns, drop_columns: [:account_sym, :currency, :subindex, :schema, :source, :priority])
    main_columns = [:date, :amount, :description]
    main_columns.unshift(:id) if txns.count{|t| t[:id]} > txns.count * 2 / 3
    drop_columns.concat(main_columns)

    data = txns.map do |t| 
      remainder = {}.merge(t.data)
      remainder = remainder.delete_if{|k,v| v.nil? || ((v.is_a?(Array) || v.is_a?(String)) && v.empty?) }
      remainder.each_pair{ |k,v| remainder[k] = t.schema.format_field(k,v)}


      row = Hash[main_columns.map{|k| remainder.key?(k) ? [k, remainder[k]] : nil}.compact]
      drop_columns.each{|c| remainder.delete(c)}
      remainder = Hash[remainder.to_a.sort_by{|p| p[0]}]
      row[:json] = JSON.generate(remainder)
      row
    end
    pretty_tsv((main_columns + [:json]).map{|name| {name: name.to_s.split.map(&:capitalize).join(' ')}}, data)
  end



  def pretty_reconcile_tsv(records)
    pretty_tsv([{name: "Date", format: lambda {|v| v.strftime("%Y-%m-%d")}},
         {name:"Amount", format: "%.2f"},
         {name:"Balance",  format: "%.2f"},
         {name:"Discrepancy", format: "%.2f"},
         {name:"Description"},
         {name:"Source"},
         {name:"Id"},
          ], records)
  end

  def pretty_tsv(types, records)

    widths = types.map{ |t| t[:name].length }
    table = records.compact.map do |r|
      row = []
      types.each_with_index do |t,i|
        if t[:fn] 
          value = (t[:fn]).call(r)
        else 
          key = t[:key] || t[:name].to_s.downcase.gsub(/ /,"_").to_sym
          format = t[:format]
          #Convert to string using provided format string or lambda
          value = key.kind_of?(Array) ? r[key.detect{|k| !r[k].to_s.empty?   }] : r[key] 
          #p [key,key.first{|k| !r[k].to_s.empty?   }, r[key[0]].to_s, r] if value.to_s.empty? && key.kind_of?(Array)
          value = format % value if value && format && format.is_a?(String)
          value = format.call(value) if value && format && format.respond_to?(:call)
        end 
        value ||= ""
        value = value.to_s.gsub(/\t\r\n/,"") 
        row << value
        #check length
        widths[i] = [widths[i] || 0, value.length].max
      end
      row
    end

    #Now we hav a table of strings and widths
    output = ""
    output << types.each_with_index.map { |t,i| t == types.last ? t[:name] : t[:name].ljust(widths[i]) } * "\t"
    output << "\n"
    table.each do |row|
      row.each_with_index do |v,i|
        output << ((i == widths.length - 1) ? v.to_s : (v.ljust(widths[i]) + "\t"))
      end
      output << "\n"
    end
    output
  end

  def pretty_tsv_from_arrays(headers, rows)
    #Stringify and remove invalid characters
    table = ([headers] + rows).map do |r|
      r.map{|v| (v || "").to_s.gsub(/\t\r\n/,"")}
    end
    #calculate widths
    widths = []
    table.each do |newrow|
      newrow.each_with_index do |v, ix|
        widths[ix] = [widths[ix] || 0, v.length].max
      end
    end
    output = ""
    table.each do |row|
      row.each_with_index do |v,i|
        output << ((i == widths.length - 1) ? v.to_s : (v.ljust(widths[i]) + "\t"))
      end
      output << "\n"
    end
    output
  end

  def get_tags(txn)
    tags = txn[:tags] || []
    tags << :transfer if txn[:transfer]
    tags << :unpaired if txn[:transfer] && !txn[:transfer_pair]
    tags.uniq
  end

  def generate_csv(txns, schema, field_names) 
    CSV.generate do |csv|
      csv << field_names
      txns.each do |t|
        csv << field_names.map{|f| schema.format_field(f, t[f])}
      end
    end
  end

  def write_file(path, contents)
    FileUtils::mkdir_p File.dirname(path) unless Dir.exist?(File.dirname(path))

    File.open(path, 'w') { |f| f.write(contents) }
  end 

  def write_all(file, rows)
     output = pretty_tsv([{name: "Date", format: lambda {|v| v.strftime("%Y-%m-%d")}},
             {name:"Amount", format: "%.2f"},
             {name:"Description"},
             {name:"Balance After", key: [:balance_after, :balance], format: "%.2f"},
             {name:"Tags", fn: lambda {|t| get_tags(t).map{|f|f.to_s}.join(",")}},
             {name:"Tax Expense", key: [:tax_expense]},
             {name:"Subledger", key: [:subledger]},
             {name:"Vendor", key: [:vendor]},
             {name:"Vendor Focus", key: [:vendor_focus]},
             {name:"Client", key: [:client]}
             #{name:"Extra", fn: lambda {|t| t[:chase_tag] }}
             ],rows)
    write_file(file, output)
  end


  def write_augmented_rows(file, rows)
     output = pretty_tsv([{name: "Date", format: lambda {|v| v.strftime("%Y-%m-%d")}},
             {name:"Amount", format: "%.2f"},
             {name:"Description"},
             {name:"Balance After", key: [:balance_after, :balance], format: "%.2f"},
             {name:"Tax Expense", key: [:tax_expense]},
             {name:"Tags", fn: lambda {|t| get_tags(t).map{|f|f.to_s}.join(",")}},
             {name:"Vendor", key: [:vendor]}
             #{name:"Extra", fn: lambda {|t| t[:chase_tag] }}
             ],rows)

    File.open(file, 'w') { |f| f.write(output) }
  end

  def write_augmented(file, transactions, statements)
     output = pretty_tsv([{name: "Date", format: lambda {|v| v.strftime("%Y-%m-%d")}},
             {name:"Amount", format: "%.2f"},
             {name:"Description"},
             {name:"Balance After", key: [:balance_after, :balance], format: "%.2f"},
             {name:"Tax Expense", key: [:tax_expense]},
             {name:"Vendor", key: [:vendor]},
             {name:"Tags", fn: lambda {|t| get_tags(t).map{|f|f.to_s}.join(",")}}
             
             ],(transactions + statements).stable_sort_by { |t| t[:date].strftime("%Y-%m-%d") })

    File.open(file, 'w') { |f| f.write(output) }
  end

  

  def write_normalized(file, transactions, statements)
     output = pretty_tsv([{name: "Date", format: lambda {|v| v.strftime("%Y-%m-%d")}},
             {name:"Amount", format: "%.2f"},
             {name:"Description"},
             {name:"Balance After", key: [:balance_after, :balance], format: "%.2f"}
             ],(transactions + statements).stable_sort_by { |t| t[:date].strftime("%Y-%m-%d") })

    File.open(file, 'w') { |f| f.write(output) }
  end


  def write_transfers(file, transfers)
     output = pretty_tsv([
      {name:"Account", key: :account_sym},
      {name: "Date", format: lambda {|v| v.strftime("%Y-%m-%d")}},
       {name:"Amount", format: "%.2f"},
       {name:"Description"},
       {name:"Balance After", key: [:balance_after, :balance], format: "%.2f"}
       ],transfers)

    File.open(file, 'w') { |f| f.write(output) }
  end



end 
