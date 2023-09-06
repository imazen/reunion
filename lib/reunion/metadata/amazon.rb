#Generate intersection files
# require 'pry'
module Reunion
  module Metadata

    # The shipments and items parsers rely on the CSV exports that no longer exist.
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
        {
          headers: :first_row, 
          header_converters:
          ->(h){ h.nil? ? nil : h.encode('UTF-8').downcase.strip.gsub(/\s+/, "_").gsub(/\W+/, "").to_sym}
        }
      end 
    end 

    class AmazonShipmentsParser < AmazonParserBase
      def parse(text)
        CSV.parse(text.rstrip, **csv_options).map do |row|
          {
            amount: parse_amount(row[:total_charged]),
            subtotal: parse_amount(row[:subtotal]),
            card: (row[:payment_instrument_type] || "").strip,
            order_id: row[:order_id].strip,
            order_date: parse_date(row[:order_date]),
            ship_date: parse_date(row[:shipment_date]),
            date: get_nearest_date(row)
          }
        end
      end
    end
    

    class AmazonItemsParser < AmazonParserBase
      def parse(text)
        CSV.parse(text.rstrip,**csv_options).map do |row|
          {
            amount: parse_amount(row[:item_subtotal]),
            description: row[:title]&.strip,
            order_id: row[:order_id].strip,
            seller: (row[:seller] || "Amazon.com").strip,
            order_date: parse_date(row[:order_date]),
            ship_date: parse_date(row[:shipment_date]),
            date: get_nearest_date(row)
          }
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
          # First just try subsequences
          for start_at in (0..(items.length -  find_item_count)) do
            subsequence = items[start_at,find_item_count]
            total = subsequence.inject(0){ |sum, item| sum + item[:amount] }
            return subsequence if total == desired_sum
          end

          # Then combinatorial
          inner_combination_count = factorial(items.length) / (factorial(items.length - find_item_count) * factorial(find_item_count))
          if inner_combination_count > 100000
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
        # Find correlated items by date and order_id. When there are multiple shipments for 
        # an order on the same day, we have to use math to figure out which 
        # items add up. We can combinatorially combine them to solve the problem

        #TODO: Sometimes it's just the order total, we need to add rows for that
        
        # Try all items in a single charge for the order
        order_level_txns = shipments.group_by { |box| box[:order_id] }.flat_map do |order_id, order_boxes|
          first_box = order_boxes.first

          all_order_items = items.select { |item| item[:order_id] == order_id }

          dates = [
                    first_box[:order_date],
                    first_box[:order_date] + 1,
                    first_box[:date],
                    first_box[:date] > first_box[:order_date] ? first_box[:date] - 1 : nil,
                    first_box[:date] + 1,
                    first_box[:date] + 2,
                    first_box[:date] + 3,
                    first_box[:date] + 4
                  ].uniq.compact
          
          order_total = order_boxes.inject(0) { |sum, box| sum + box[:amount] }

          dates.map do |date|
            Transaction.new(
              schema: schema, 
              date: date,
              amount: -1 * order_total,
              card: first_box[:card],
              description: "AMAZON.COM",
              description2: "#{all_order_items.nil? ? '??' : ''}Order #{order_id}: " + describe(all_order_items)
            )
          end
          
        end
        
        # Try boxes of items, billed per shipment
        box_level_txns = shipments.flat_map do |box|
          candidates = items.select { |item| item[:date] == box[:date] && item[:order_id] == box[:order_id] }
          in_the_box = find_subset(candidates, box[:subtotal])

          dates = [box[:order_date], 
                    box[:order_date] + 1, 
                    box[:date], 
                    box[:date] > box[:order_date] ? box[:date] - 1: nil, 
                    box[:date] + 1,
                    box[:date] + 2,
                    box[:date] + 3,
                    box[:date] + 4].uniq.compact



          dates.map do |date|
            Transaction.new(schema: schema, date: date,
             amount: -1 * box[:amount],
             card: box[:card],
             description: "AMAZON.COM",
             description2: "#{in_the_box.nil? ? '??' : '' }Order #{box[:order_id]}: " + describe(in_the_box || candidates)
            )
          end
        end

        order_level_txns + box_level_txns
      end
    end
  end

  # For the request-my-data format
  class RetailOrderHistory

    # Shipment Item Subtotal (decimal)
    # Shipment Item Subtotal Tax  (decimal)
    # Payment Instrument Type (' and ' delimited strings, e.g. "Visa - 1234 and Gift Certificate" etc)
    # Product Name (string)
    # Order ID  (string)
    # Order Date  (YYYY-MM-DDThh:mm:ss+00:00Z format)

    # Ship Date (YYYY-MM-DDThh:mm:ss+00:00Z format)


    def initialize(items, shipments, schema)
      @items = items
      @shipments = shipments
      @schema = schema
    end

    def aggregate
      AmazonAggregator.new.aggregate(@items, @shipments, @schema)
    end
  end
end
