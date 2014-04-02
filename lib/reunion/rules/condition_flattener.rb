module Reunion
  module Re
    class ConditionFlattener

      def condition_tree_to_array_of_arrays(tree)

          tree = eliminate_nots(tree, state: false)
          tree = eliminate_singles(tree)
          tree = flatten(Or, tree)
          tree = flatten(And, tree)
          return [[tree]] if Cond === tree
          return tree.conditions.map{|c| [c]} if Or === tree

          return [[]] if tree.nil?

          raise "Failed to collapse to 1 AND: #{tree.inspect}" unless And === tree 

          #should result in one and containing lots of ors. 
          permute_ors(tree.conditions)
      end


      def eliminate_nots(f,state: false)
        if Cond === f
          f.not = !!f.not
          f.not = !f.not if state
          f
        elsif Not === f
          eliminate_nots(f.condition, state: !state)
        elsif And === f || Or === f
          f.conditions = f.conditions.map{|c| eliminate_nots(c)}
          f
        else
          raise "Unexpeted expression type #{f.inspect}"
        end
      end

      def eliminate_singles(f)
        if (And === f || Or === f)
          f.conditions = f.conditions.map{|e| eliminate_singles(e)}.compact
          if f.conditions.length == 0
            nil
          elsif f.conditions.length == 1
            f.conditions.first
          else
            f
          end
        else
          f
        end
      end


      def flatten(type, f)
        if type === f
          f.conditions = f.conditions.map{|e| flatten(type,e)}.map{|e| type === e ? e.conditions : e}.flatten
          f
        else
          f
        end
      end

      def permute_ors(array_of_ors)
        array_of_ors = array_of_ors.map do |e| 
          next e.conditions if Or === e
          next [e] if Cond === e
          raise "Error, unexpected type #{e}"
        end
        #STDERR << array_of_ors.inspect
        array_of_ors.length > 1 ? array_of_ors.first.send(:product, *array_of_ors[1..-1]) : array_of_ors.flatten.map{|e| [e]}
      end 

    

    end 
  end
end