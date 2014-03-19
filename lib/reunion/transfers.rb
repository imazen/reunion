module Reunion
  class Organization
    def get_transfer_pairs(transfers, all_transactions)

      #Match up transfers
      transfer_pairs = []

      transfers.each_with_index do |t, ix|
        next if t[:transfer_pair]

        nearby = transfers.select {|other| other[:account_sym] != t[:account_sym] && !other[:transfer_pair] && (other[:date] - t[:date]).to_i.abs < 15}

        nearby.sort_by! { |other| (other[:date] - t[:date]).to_i.abs }

        other = nearby.detect { |other| other[:amount] == -1 * t[:amount]}

        #Look outside likely transfers
        if !other
            reg_nearby = all_transactions.select { |b| 
                b[:account_sym] != t[:account_sym] && !b[:transfer_pair] && 
                (b[:date] - t[:date]).to_i.abs < 15 && !b.tags.include?(:not_transfer)}

            reg_nearby.sort_by! { |b| (b[:date] - t[:date]).to_i.abs }
            other = reg_nearby.detect { |b| b[:amount] == -1 * t[:amount]}
            transfers << other if other
        end

        if other
            t[:transfer_pair] = other
            other[:transfer_pair] = t 
            t[:transfer] = other[:transfer] = true
            #t[:transfer_pair_id] = other[:transfer_pair_id] = t.date_str + SecureRandom.hex
            t[:tags] ||= []
            t[:tags] << :transfer
            other[:tags] ||= []
            other[:tags] << :transfer
            transfer_pairs << [other, t] 
        end 
        #p t if t[:date].strftime("%Y-%m-%d") == "2012-01-28"
      end


      return transfer_pairs, transfers
    end
  end
end

