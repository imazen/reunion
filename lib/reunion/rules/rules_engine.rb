module Reunion

  class Rule
    attr_accessor :condition, :actions, :chain

    def initialize(chain_array)
      @chain = chain_array 
      @condition = Re::And.new(chain.select{|i| i[:is_filter]}.map{|f| f[:conditions]})
      @actions = chain.select{|i| i[:is_action]}
      @modified_transactions ||= []
      @changed_transactions ||= []
      @matched_transactions ||= []
    end 

    attr_accessor :matched_transactions, :modified_transactions, :changed_transactions

    def modify(txn)
      @matched_transactions << txn
      @modified_transactions << txn
      actual_change = false
      @actions.each do |action|
        #puts "Performing action"
        actual_change = true if action[:definition].apply_action.call(txn, action[:arguments])
      end
      @changed_transactions << txn if actual_change
      actual_change
    end 

    def inspect
      "#{@condition.inspect} -> action"
    end
  end 
  class RuleEngine
    attr_accessor :rules, :tree
    def initialize(rules)
      rules.flush(true)
      @rules = rules.rules.map{|r| Rule.new(r)}
      @builder = Reunion::Re::DecisionTreeBuilder.new
      @rules.each{|r| @builder.add_rule(r.condition, r)}

      @tree = @builder.build
    end


    def prep_transactions(transactions)
      return [] if transactions.empty?
      schema = transactions.first.schema
      prep_fields_methods = schema.fields.to_a.map{|field,v| v.query_methods.map{|smd| smd.prep_data}.compact.map{|m| [field,m]}}.flatten(1)

      transactions.map{|t|
        prepped = t.data.clone
        prep_fields_methods.each{ |field, method| method.call(field, prepped[field], prepped)}
        prepped[:_txn] = t
        prepped
      }
    end 

    #TODO apply source data sanitization
    def run(transactions)
      
      current_set = transactions
      next_set = []
      max_iterations = 3
      max_iterations.times do |i|
        current_set = prep_transactions(current_set)
        break if current_set.empty?
        next_set = current_set.select{|t| modify_txn(t)}.map{|t| t[:_txn]}
        #puts "#{next_set.length} of #{current_set.length} transactions modified. Rule count = #{rules.length}"
        current_set = next_set
      end
    end 
    def modify_txn(t)
      modified = false
      @tree.get_results(t) do |rule|
        m = rule.modify(t[:_txn])
        modified = true if m
      end
      modified
    end 
    def find_matches(transactions)
      transactions.select do |t|
        matches = false
        @tree.get_results(t) do |rule|
          matches = true
        end
        matches
      end
    end 

  end 
end
