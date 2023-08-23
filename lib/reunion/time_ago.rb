module Reunion
    module TimeAgo
        def self.ago_in_words(value)
          return '(never)' if value.nil?
          return 'vv long ago' if value.year < 1800
          secs = Time.now - value
          return 'just now' if secs > -1 && secs < 3
          return '' if secs <= -1
          pair = ago_in_words_pair(secs)
          ary = ago_in_words_singularize(pair)
          ary.size == 0 ? '' : ary.join(' ') << ' ago'
        end
      
        private
      
        # @private
        def self.ago_in_words_pair(secs)
          [[60, :s], [60, :m], [24, :h], [100_000, :d]].map{ |count, name|
            if secs > 0
              secs, n = secs.divmod(count)
              "#{n.to_i}#{name}"
            end
          }.compact.reverse[0..1]
        end
      
        # @private
        def self.ago_in_words_singularize(pair)
          if pair.size == 1
            pair.map! {|part| part[0, 2].to_i == 1 ? part.chomp('s') : part }
          else
            pair.map! {|part| part[0, 2].to_i == 1 ? part.chomp('s') : part[0, 2].to_i == 0 ? nil : part }
          end
          pair.compact
        end
        
    end 
end 