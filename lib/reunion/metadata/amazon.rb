#Generate intersection files
require 'pry'
module Reunion
  module Metadata

    class AmazonParserBase
      def parse_amount(text)
        return 0 if text.nil? || text.empty?
        BigDecimal.new(text.gsub(/[\$,]/, ""))
      end

      def csv_options
        {headers: :first_row, 
         header_converters:
          ->(h){ h.nil? ? nil : h.encode('UTF-8').downcase.strip.gsub(/\s+/, "_").gsub(/\W+/, "").to_sym}
        }
      end 
    end 

    class AmazonShipmentsParser < AmazonParserBase
      def parse(text)
        CSV.parse(text.rstrip, csv_options).map do |row|
          {amount: parse_amount(row[:total_charged]),
            subtotal: parse_amount(row[:subtotal]),
          card: (row[:payment_instrument_type] || "").strip,
          order_id: row[:order_id].strip,
          date: Date.strptime(row[:shipment_date], '%m/%d/%y')}
        end
      end
    end
    

    class AmazonItemsParser < AmazonParserBase
      def parse(text)
        CSV.parse(text.rstrip, csv_options).map do |row|
          {amount: parse_amount(row[:item_subtotal]),
          description: row[:title].strip,
          order_id: row[:order_id].strip,
          seller: (row[:seller] || "Amazon.com").strip,
          date: row[:shipment_date] ?  Date.strptime(row[:shipment_date], '%m/%d/%y') : nil}
        end.select{|row| row[:date]}
      end
    end
    class AmazonAggregator
      def factorial(n)

        n == 0 ? 1 : (1..n).inject(:*)
      end
      def find_subset(items, desired_sum)
        return nil if items.length == 0

        (1..items.length).each do |find_item_count|
          inner_combination_count = factorial(items.length) / (factorial(items.length - find_item_count) * factorial(find_item_count))
          if inner_combination_count > 100000

            STDERR << "Too many combinations (#{inner_combination_count}) required to find #{find_item_count} items of #{items.length} which total #{format_usd(desired_sum)} in order #{items[0][:order_id]}\n" 
            return nil
          end 

          items.combination(find_item_count) do |set|
            total = set.inject(0){|sum, item| sum + item[:amount]}

            
            return set if total == desired_sum
          end 
        end 
        return nil #No perfect total
      end 
      def format_usd (value)
        value.nil? ? "" : ("$%.2f" % value)

      end

      def describe(candidates)
        candidates.map do |item|
          "#{format_usd(item[:amount])}: #{item[:description]}"
        end.join(" || ")
      end 

      def aggregate(items, shipments, schema, duplicate_forward_days = 0)
        #Find correlated items by date and order_id. When there are multiple shipments for 
        #an order on the same day, we have to use math to figure out which 
        #items add up. We can combinatorially combine them to solve the problem
        shipments.map do |box|
          candidates = items.select{|item| item[:date] == box[:date] && item[:order_id] == box[:order_id]}
          in_the_box = find_subset(candidates, box[:subtotal])

          (0..duplicate_forward_days).map do |days|
            Transaction.new(schema: schema, date: box[:date] + days,
             amount: -1 * box[:amount],
             card: box[:card],
             description: candidates.any?{|item| item[:seller] != "Amazon.com"} ? "AMAZON MKTPLACE PMTS" : "Amazon.com",
             description2: "#{in_the_box.nil? ? '??' : '' }Order #{box[:order_id]}: " + describe(in_the_box || candidates)
            )
          end
        end.flatten
      end 
    end
  end
end
