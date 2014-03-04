class Reunion::Export

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
    output << types.each_with_index.map { |t,i| t[:name].ljust(widths[i]) } * "\t"
    output << "\n"
    table.each do |row|
      row.each_with_index do |v,i|
        output << v.ljust(widths[i]) 
        output << "\t" unless (i == widths.length - 1)
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
