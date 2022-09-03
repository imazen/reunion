module Reunion
  class Organization
    def get_transfer_pairs(transfers, all_transactions)

      transfer_window = 15
      #Match up transfers
      transfer_pairs = []

      looked_outside_transfer_txns = 0

      transfers.each_with_index do |t, ix|
        next if t[:transfer_pair]

        nearby = transfers.select { |other| other[:account_sym] != t[:account_sym] && !other[:transfer_pair] && (other[:date] - t[:date]).to_i.abs < transfer_window}

        nearby.sort_by! { |other| (other[:date] - t[:date]).to_i.abs }

        other = nearby.detect { |other| other[:amount] == -1 * t[:amount]}

        # Look outside likely transfers
        if !other
          looked_outside_transfer_txns += 1
          reg_nearby = all_transactions.select { |b| 
              b[:account_sym] != t[:account_sym] && !b[:transfer_pair] && 
              (b[:date] - t[:date]).to_i.abs < transfer_window && !b.tags.include?(:not_transfer)}

          reg_nearby.sort_by! { |b| (b[:date] - t[:date]).to_i.abs }
          other = reg_nearby.detect { |b| b[:amount] == -1 * t[:amount]}
          transfers << other if other
          # STDERR < "LOOKED "
        end

        if other
            t[:transfer_pair] = other
            other[:transfer_pair] = t 
            t[:transfer] = other[:transfer] = true
            # t[:transfer_pair_id] = other[:transfer_pair_id] = t.date_str + SecureRandom.hex
            t[:tags] ||= []
            t[:tags] << :transfer
            other[:tags] ||= []
            other[:tags] << :transfer
            transfer_pairs << [other, t] 
        end 
        # p t if t[:date].strftime("%Y-%m-%d") == "2012-01-28"
      end

      STDERR << "Looked outside of transfer transactions for a pair half #{looked_outside_transfer_txns} times\n"
      return transfer_pairs, transfers
    end
  end
end

