module Reunion
  module Re
    #eq, gt, lt,  between_inclusive include, regex, prefix, lambda, yes
    Cond = Struct.new(:key, :comparator, :value, :not)
    And = Struct.new(:conditions)
    Or = Struct.new(:conditions)
    class Yes < Cond
      def initialize
        @key = nil
        @comparator = :yes
        @value = nil
      end
    end 
    Not = Struct.new(:condition)

    class Cond
      def inspect
        "<#{key} #{@not ? '!' : ''}#{comparator} #{value}>"
      end
    end
    class And
      def inspect
        "AND(" +  conditions.inspect + ")"
      end
    end
    class Or
      def inspect
        "OR(" + conditions.inspect + ")"
      end
    end
    class Not
      def inspect
        "AND(" + condition.inspect + ")"
      end
    end


    class DecisionTreeBuilder

      def initialize
        @chains = []
        @root = DecisionNode.new
        @root.children = []
        @root.results = []
        @root.chains_touching = @chains
        @root.comparator = :yes
      end


      Chain = Struct.new(:conditions, :result, :node)

      def add_rule(condition, result)
        paths = ConditionFlattener.new.condition_tree_to_array_of_arrays(condition)
        paths.each do |path|
          @chains << Chain.new(path, result, nil)
        end
      end 

    
      class DecisionNode

        def initialize(parent = nil)
          @parent = parent
          @children = []
          @results = []
          @chains_touching = []
        end


        def add_subnodes
          sorted = components_by_reusability(@chains_touching, parent.nil? ? nil : self)
          sorted.each do |info|
            add_subnodes_from_pairs(info.pairs)
          end
        end

        def add_subnodes_from_pairs(possible_pairs)
          pairs = possible_pairs.select{ |condition, chain| chain.node == self || (chain.node == nil && parent == nil)}
          conditions = pairs.map { |co, chain| co }.uniq.compact
          if conditions.length == 1
            add_simple_subnode(conditions.first,pairs)
          elsif conditions.length > 1 && (conditions.first.comparator == :eq || conditions.first.comparator == :prefix)
            add_hash_subnodes(pairs)
          elsif conditions.length > 1
            raise "Unsupported shared comparator #{conditions}"
          end
        end

        def add_simple_subnode(condition, pairs)
          n = DecisionNode.new(self)
          n.value = condition.value
          n.key = condition.key
          n.comparator = condition.comparator
          pairs.each do |c, chain|
            chain.conditions.delete(c)
            chain.node = n
            n.results << chain.result if chain.conditions.empty?
          end
          children << n
          n.chains_touching = pairs.map { |c, chain| chain}
          n.add_subnodes
        end

        def add_hash_subnodes(pairs)
          p = DecisionNode.new(self)
          children << p

          # Collect duplicate values into hash
          hash = {}
          pairs.each do |condition, chain|
            hash[condition] ||= []
            hash[condition] << chain
          end

          # Create new hash based on conditions
          nodes_by_value = {}

          hash.each do |condition, chains|
            remaining_chains = chains.select { |chain| chain.node == self || (chain.node.nil? && parent.nil?) }
            next if remaining_chains.count < 1

            n = DecisionNode.new(p)
            n.comparator = :yes
            n.chains_touching = remaining_chains
            remaining_chains.each do |chain|
              chain.conditions.delete(condition)
              chain.node = n
              n.results << chain.result if chain.conditions.empty?
            end
            p.children << n
            n.add_subnodes

            raise "duplicate node for condition #{condition.value} #{condition} found: #{nodes_by_value[condition.value].inspect}" if !nodes_by_value[condition.value].nil?
            
            nodes_by_value[condition.value] = n
          end

          first_co = pairs.first[0]
          p.key = first_co.key 

          if first_co.comparator == :eq
            p.comparator = :in_hash
            p.value = nodes_by_value
          elsif first_co.comparator == :prefix
            p.comparator = :in_trie
            t = Triez.new value_type: :object
            nodes_by_value.each do |k, v|
              t[k] = v
            end
            p.value = t
          else
            raise "Huh?"
          end
        end


        # eq, gt, lt,  between_inclusive, in_hash include, regex, prefix, in_trie,  lambda, yes
        attr_accessor :key, :comparator, :value, :not, :results, :children, :parent, :chains_touching


        def inspect(indent=0)
          bang = !!@not ? '!' : ''

          (" " * indent) + ">#{key} #{bang}#{comparator} #{value} -> #{results.count} results\n" +
              children.map { |c| c.inspect(indent + 2)}.join("\n")
        end


        def match?(data)
          return true if @comparator == :yes

          d = @comparator == :lambda && @key.nil? ? data : data[@key]

          return d == @value if @comparator == :eq

          return false if d.nil? # No other comparators work with a nil data

          case @comparator
          when :yes
            true
          when :eq
            d == @value
          when :lt
            d < @value
          when :gt
            d > @value
          when :between_inclusive
            d >= @value[0] && d <= @value[1]
          when :include
            d.include?(@value)
          when :regex
            @value =~ d
          when :prefix
            d.start_with?(@value)
          when :lambda
            @value.call(d)
          when :in_hash
            raise 'in_hash not supported match?'
          when :in_trie
            raise 'in_trie not supported by match?'
          end
        end

        def get_results(data, &block)
  
          if @comparator == :in_hash
            sub_value = @value[data[@key]]
            raise "Not a node: #{sub_value.inspect}" unless sub_value.nil? || sub_value.respond_to?(:get_results)

            sub_value&.get_results(data, &block)
            return false
          end
          if @comparator == :in_trie
            pairs = @value.walk(data[@key])
            pairs.each do |_, match_node|
              match_node.get_results(data, &block)
            end
            return false
          end

          return unless match?(data)

          results.each(&block)
          @children.each { |c| c.get_results(data, &block) }
        end

        Stat = Struct.new(:counter, :pairs)

        def components_by_reusability(chains, in_node)
          stats = {}
          chains.each do |chain|
            next if chain.node != in_node
            raise "TypeError #{chain.conditions.inspect}" unless Array === chain.conditions 

            chain.conditions.each do |c|
              key = get_condition_reuse_hash(c)
              info = stats[key] || Stat.new(0, [])
              stats[key] ||= info
              info.counter += 1
              info.pairs << [c,chain]
            end
          end
          by_most_used = stats.values.sort_by(&:counter).reverse
          by_most_used
        end
      
        def get_condition_reuse_hash(c)
          if c.comparator == :eq && !c.not
            "#{c.key}|eq|*"
          elsif c.comparator == :prefix && !c.not
            "#{c.key}|eq|^"
          else
            c
          end
        end 
      end 


      def build
        @root.add_subnodes
        @root
      end 


    end 



  end
end