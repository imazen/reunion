#Generate intersection files
# require 'pry'
module Reunion
  module Metadata

    class AmazonParserBase
      def parse_amount(text)
        return 0 if text.nil? || text.empty?
        BigDecimal(text.gsub(/[\$,]/, ""))
      end

      def parse_date(text)
        text ? Date.strptime(text, '%m/%d/%y') : nil
      end 

      def get_nearest_date(row)
        parse_date(row[:shipment_date]) || parse_date(row[:order_date])
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
        CSV.parse(text.rstrip,**csv_options).map do |row|
          {amount: parse_amount(row[:total_charged]),
            subtotal: parse_amount(row[:subtotal]),
          card: (row[:payment_instrument_type] || "").strip,
          order_id: row[:order_id].strip,
          order_date: parse_date(row[:order_date]),
          ship_date: parse_date(row[:shipment_date]),
          date: get_nearest_date(row)}
        end
      end
    end
    

    class AmazonItemsParser < AmazonParserBase
      def parse(text)
        CSV.parse(text.rstrip,**csv_options).map do |row|
          {amount: parse_amount(row[:item_subtotal]),
          description: row[:title]&.strip,
          order_id: row[:order_id].strip,
          seller: (row[:seller] || "Amazon.com").strip,
          order_date: parse_date(row[:order_date]),
          ship_date: parse_date(row[:shipment_date]),
          date: get_nearest_date(row)}
        end.select{|row| row[:date]}
      end
    end
    class AmazonAggregator
      def factorial(n)
        n.zero? ? 1 : (1..n).inject(:*)
      end

      def find_subset(items, desired_sum)
        return nil if items.empty?

        (1..items.length).each do |find_item_count|
          inner_combination_count = factorial(items.length) / (factorial(items.length - find_item_count) * factorial(find_item_count))
          if inner_combination_count > 500000

            $stderr << "Too many combinations (#{inner_combination_count}) required to find #{find_item_count} items of #{items.length} which total #{format_usd(desired_sum)} in order #{items[0][:order_id]} shipped #{items[0][:ship_date]}\n" 
            return nil
          end

          items.combination(find_item_count) do |set|
            total = set.inject(0){ |sum, item| sum + item[:amount] }
            return set if total == desired_sum
          end
        end
        nil #No perfect total
      end

      def format_usd(value)
        value.nil? ? "" : ("$%.2f" % value)
      end

      def describe(candidates)
        candidates.map do |item|
          "#{format_usd(item[:amount])}: #{item[:description]}"
        end.join(" || ")
      end 

      def aggregate(items, shipments, schema)
        #Find correlated items by date and order_id. When there are multiple shipments for 
        #an order on the same day, we have to use math to figure out which 
        #items add up. We can combinatorially combine them to solve the problem
        shipments.map do |box|
          candidates = items.select{|item| item[:date] == box[:date] && item[:order_id] == box[:order_id]}
          in_the_box = find_subset(candidates, box[:subtotal])

          dates = [box[:order_date], 
                    box[:order_date] + 1, 
                    box[:date], 
                    box[:date] > box[:order_date] ? box[:date] - 1: nil, 
                    box[:date] + 1].uniq.compact



          dates.map do |date|
            Transaction.new(schema: schema, date: date,
             amount: -1 * box[:amount],
             card: box[:card],
             description: candidates.any?{|item| item[:seller] != "Amazon.com"} ? "AMAZON MKTPLACE PMTS - AMZN.COM/BILL, WA" : "AMAZON.COM - AMZN.COM/BILL, WA",
             description2: "#{in_the_box.nil? ? '??' : '' }Order #{box[:order_id]}: " + describe(in_the_box || candidates)
            )
          end
        end.flatten
      end 
    end
  end
end
