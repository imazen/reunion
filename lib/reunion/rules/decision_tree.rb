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
          pairs = possible_pairs.select{|condition,chain| chain.node == self || (chain.node == nil && parent == nil)}
          conditions = pairs.map{|co,chain|co}.uniq.compact
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
          pairs.each do |c,chain|
            chain.conditions.delete(c)
            chain.node = n
            n.results << chain.result if chain.conditions.empty?
          end
          self.children << n 
          n.chains_touching = pairs.map{|c,chain| chain}
          n.add_subnodes
        end
        def add_hash_subnodes(pairs)
          h = {}
          pairs.each do |c,chain|
            h[c] ||= []
            h[c] << chain
          end

          p = DecisionNode.new(self)
          self.children << p
          h.each do |co,chains|
            remaining_chains = chains.select{|chain| chain.node == self || (chain.node == nil && parent == nil)}
            next if remaining_chains.count < 1
            h[co] = n = DecisionNode.new(p)
            n.comparator = :yes
            n.chains_touching = remaining_chains
            remaining_chains.each do |chain|
              chain.conditions.delete(co)
              chain.node = n
              n.results << chain.result if chain.conditions.empty?
            end
            p.children << n
            n.add_subnodes
          end

          first_co = pairs.first[0]
          p.key = first_co.key 

          if first_co.comparator == :eq
            p.comparator = :in_hash
            p.value = Hash[h.to_a.map{|k,v| [k.value,v]}]
          elsif first_co.comparator == :prefix
            p.comparator = :in_trie
            t = Triez.new value_type: :object
            h.each do |k,v|
              t[k.value] = v
            end
            p.value = t
          else
            raise "Huh?"
          end 
        end


        #eq, gt, lt,  between_inclusive, in_hash include, regex, prefix, in_trie,  lambda, yes
        attr_accessor :key, :comparator, :value, :not, :results, :children, :parent, :chains_touching


        def inspect(indent=0)
          bang = !!@not ? "!" : ""

          return (" " * indent) + ">#{key} #{bang}#{comparator} #{value} -> #{results.count} results\n" + 
              children.map{|c| c.inspect(indent + 2)} * "\n"
        end

        def get_results(data, &block)
          node = self
          d = ((@comparator == :lambda || @comparator == :yes) && @key.nil?) ? data : data[@key]
          match = case @comparator
          when :yes
            true
          when :eq
            d == @value
          when :lt
            d < @value
          when :gt
            d > @value
          when :between_inclusive
            !d.nil? && d >= @value[0] && d <= @value[1]
          when :include
            d && d.include?(@value)
          when :regex
            @value === d
          when :prefix
            d && d.start_with?(@value) 
          when :lambda
            @value.call(d)
          when :in_hash
            node = @value[d]
            node.get_results(data,&block) unless node.nil?
            false
          when :in_trie
            pairs = @value.walk(d) 
            pairs.each do |k, node|
              node.get_results(data,&block)
            end
            false
          end
          if match
            results.each(&block)
            @children.each{|c|c.get_results(data,&block)}
          end

        end

        Stat = Struct.new(:counter, :pairs)

        def components_by_reusability(chains, in_node)
          stats = {}
          chains.each do |chain|
            next if chain.node != in_node
            raise "TypeError #{chain.conditions.inspect}" unless Array ===chain.conditions 
            chain.conditions.each do |c|
              key = get_condition_reuse_hash(c)
              info = stats[key] || Stat.new(0, [])
              stats[key] ||= info
              info.counter += 1
              info.pairs << [c,chain]
            end
          end
          by_most_used = stats.values.sort_by(&:counter).reverse
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