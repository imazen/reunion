module Reunion

  class DelegateAndNotify < ::SimpleDelegator
    attr_reader :notify_method
    def initialize(obj, method_to_call_on_action)
      @notify_method = method_to_call_on_action
      super(obj)
    end

    def method_missing(m, *args, &block)
      self.__getobj__.send(@notify_method)
      #begin
      #Kernel.byebug
      super(m, *args, &block)
      #ensure
      #  $@.delete_if {|t| /\A#{Regexp.quote(__FILE__)}:#{__LINE__-2}:/o =~ t} if $@
      #end
    end
  end 

  class Rules

    def initialize
      @stack = []
      @rules = []
      @searcher = nil
    end

    attr_reader :rules
    def add(&block)
      self.instance_eval(&block)
    end 


    QUERY_NOUNS = %w{all none transfer transactions focuses vendors clients tags tax_expenses subledgers match amount amount_over amount_under amount_between year date date_before date_after date_between}
    QUERY_VERBS = %w{for when exclude}
    ACTION_NOUNS = %w{vendor client subledger tax_expense as_transfer tag}
    ACTION_VERBS = %W{set use}
 
    ALIASES = {before: :for_date_before, after: :for_date_after, matches: :for_match, exclude: :exclude_transactions, :for => :for_transactions}

    def parse_step_name(name)
      name = name.to_s
      result = {}
      is_query = query_method_names.include?(name)
      is_action = action_method_names.include?(name)
      verb = (QUERY_VERBS + ACTION_VERBS).find{|v| name.start_with?(v + "_")}
      noun = name[(verb.length + 1)..-1] unless verb.nil? 
      if verb.nil?
        verb = 'for' if QUERY_NOUNS.include?(name)
        verb = 'set' if ACTION_NOUNS.include?(name)
        noun = name unless verb.nil?
      end 

      raise "Failed to parse rule name '#{name}'." unless (is_query || is_action) && verb != nil && noun != nil 
      {is_query: is_query,
       is_action: is_action,
        verb: verb.to_sym,
        noun: noun.to_sym}
    end 

    #we can't dot-chain because we can't tell if it's an endpoint or actually used. 
    #we co
    def query_method_names
      (QUERY_VERBS.map{|v| QUERY_NOUNS.map{|n| v + "_" + n}}.flatten + QUERY_NOUNS)
    end 
    def action_method_names
      (ACTION_VERBS.map{|v| ACTION_NOUNS.map{|n| v + "_" + n}}.flatten + ACTION_NOUNS)
    end 

    def dynamic_method_name_symbols
      @@cached_dynamics ||= Set.new((query_method_names + action_method_names + ALIASES.keys).map{|s|s.to_sym})
    end 

    def respond_to?(method_name)
      dynamic_method_name_symbols.include?(method_name) || super(method_name)
    end 
    def method_missing(meth, *args, &block)
      if dynamic_method_name_symbols.include?(meth)
        r = add_rule_part(meth, *args, &block)
        @next_call_proxied = false
        r
      else
        super(meth, *args, &block)
      end
    end

    #This is called if the DelegateAndNotify instance is used
    def proxy_restore_stack_from_last_rule
      @next_call_proxied = true #track this so we can adjust the stacktrace
      @stack = @rules.pop
      #TODO - this doesn't handle the case where someone assigns the result to a variable. 
      #We would need to give the rule a uid, like SecureRandom.hex, so we can remove it from the rules at any time.
      #We would also have to define how to handle exiting the stack. If we can't assume it's being used in the same 
      #context, we'd have to compare the old context to the new context to guess if they are the same. 
      #if they're different (the parent rule from the stored is different from the current stack), then we would either need
      # to replace the current stack (and restore it upon exit), or add a barrier, or graft it. 
      #Nothing is clear, so maybe we just say it's unsupported

    end 

    def add_rule_part(method, *args, &block)
      name = ALIASES[method] || method
      part = parse_step_name(name).merge(
              {name: name, 
              method_name: method, 
              arguments: args, 
              stacktrace: caller(@next_call_proxied ? 4 : 2)})

      #if block is specified, it's just part of a chain, not an endpoint
      if block
        #Just part of the chain
        @stack << part
        #begin
        r = self.instance_eval(&block)
        #rescue NoMethodError => e 
        #  e.set_backtrace(part[:stacktrace]) unless @exception_rethrown
        #  @exception_rethrown = true
        #  raise e
        #end 
        @exception_rethrown = false
        deal_with_block_result(r)
        @stack.pop
        #Do anyth
        return nil
      else
        @rules << @stack + [part]
        #Add the rule, but remove and restore the stack if something is chained
        return DelegateAndNotify.new(self, :proxy_restore_stack_from_last_rule)
      end 
    end 
    def deal_with_block_result(value)
      return if value.is_a?(DelegateAndNotify) || value.nil?
      #TODO: What's with this, what do we do with it. 
      #Implement if we have a hash shortcut syntax.
    end 

    


    # mention (add rule commentary)
    # when (condition on txn)
    # - after/before/between (date)
    # - name=vale
    # - lambda
    # - match (description)
    # set (action on matching txn)
    # - name=value
    # - mark_as_transfer
    # - vendor

    #Defining Expectations
    # Time interval
    # transaction qty. per interval
    # total cost per interval
    # per vendor


  end

  class Rule
    attr_accessor :chain
    attr_accessor :disabled

    def initialize(chain_array)

      @chain = chain_array 
      @disabled = false

      @filters = chain.select{|i| i[:is_query]}.each do |f|
        noun = f[:noun]
        args = f[:arguments]
        message = nil
        if [:all, :none, :transfers].include?(noun)
          message = "does not accept any parameters." if !args.empty?
        elsif noun == :date_between
          message = "requires 2 parameters. Received #{args.length}." if args.length == 2
        elsif [:date_before, :date_after].include?(noun)
          message = "requires 1 date parameter." if args.length != 1
        elsif noun == :transactions
          message = "requires 1 lambda parameter" if (args.length != 1 || args.respond_to?(:call))
        elsif args.empty?
          message = "requires 1 or more parameters."
        end 
        puts "Rule disabled. #{f[:method_name]} #{message} #{f[:stacktrace]}" unless message.nil?
        @disabled = true unless message.nil? 
      end 
      @actions = chain.select{|i| i[:is_action]}.each do |a|

        args = a[:arguments]
        needs_1 = a[:noun] != :as_transfer && args.length != 1
        puts "Rule disabled. #{a[:method_name]} requires 1 parameter, given #{args.inspect}. #{a[:stacktrace]}" if needs_1
        @disabled = true if needs_1
      end
      
    end 

    def evaluate_filter(f, txn, vendors, clients)
      result = evaluate_filter_noun(f,txn,vendors,clients)
      return f[:verb] == :exclude ? !result : result
    end 

    def to_date_mjd(value)
      value.is_a?(String) ? Date.parse(value).mjd : value.mjd
    end


    def evaluate_filter_noun(f, txn, vendors, clients)

      noun = f[:noun]
      args = f[:arguments]

      a = args.first

      #all none transfer
      return false if (noun == :none)
      return true if (noun == :all) ||
                (noun == :transfers && txn[:transfer])

      return true if noun == :amount && txn.amount == a
      return true if noun == :amount_over && txn.amount > a
      return true if noun == :amount_under && txn.amount < a
      return true if noun == :amount_between && txn.amount >= args.min && txn.amount <= args.max


      return true if noun == :year && txn.date.year == a.is_a?(String) ? Date.parse(a).year : a.is_a?(Date) ? a.year : nil
      return true if noun == :date && txn.date.mjd == to_date_mjd(a)
      return true if noun == :date_after && txn.date.mjd > to_date_mjd(a)
      return true if noun == :date_before && txn.date.mjd < to_date_mjd(a)
      return true if noun == :date_between && txn.date.mjd >= args.map(&to_date_mjd).min && txn.date <= args.map(&to_date_mjd).max
      
      #transactions
      return true if (noun == :transactions && args.first.call(txn))

    
      if [:focuses, :vendors, :clients, :tags, :tax_expenses, :subledgers, :match].include? noun
        data = case noun
        when :vendors
          txn.vendor
        when :clients
          txn.client
        when :tags
          txn.tags
        when :tax_expenses
          txn[:tax_expense]
        when :subledgers
          txn[:subledger]
        when :match
          txn.description
        when :focuses
          vendors[txn.vendor][:focus]
        end
        return is_match(args,data,f)
      end
      false
    end 

    def is_match(query_arguments, data, filter)
      a = query_arguments.flatten
      data = data.is_a?(Array) ? data : [data]
      a.any? do |query|
        data.any? do |value|
          case
          when query.is_a?(Regexp) 
            query =~ value 
          when query.is_a?(String) && query.length > 1 && query[0] == "^"
            query[1..-1].casecmp(value) == 0
          when query.is_a?(String) && query.length > 0  
            query.casecmp(value) == 0
          when query.is_a?(Symbol) 
            query == value
          when query.respond_to?(:call) 
            query.call(value)
          else
            trace = filter[:stacktrace] * "\n"
            puts "Unknown query type #{query.class} #{trace}"
            false
          end
        end
      end 
    end 

    def apply_action(action, txn)
      noun = action[:noun]
      args = action[:arguments]
      arg = args.first
      actual_change = false
      if noun == :as_transfer
        new_value = args.first.nil? ? true : arg
        actual_change = txn[:transfer] != new_value
        txn[:transfer] = new_value
      elsif noun == :vendor
        actual_change = txn[:vendor] != arg
        txn[:vendor] = arg
      elsif noun == :client
        actual_change = txn[:client] != arg
        txn[:client] = arg
      elsif noun == :subledger
        actual_change = txn[:subledger] != arg
        txn[:subledger] = arg
      elsif noun == :tax_expense
        actual_change = txn[:tax_expense] != arg
        txn[:tax_expense] = arg
      elsif noun == :tag
        actual_change = !txn.tags.include?(arg)
        txn.tags << arg if actual_change
      end 
      #puts "#{action[:method_name]}(#{args * ','})" if actual_change
      actual_change
    end 
    def matches?(txn, vendors,clients)
      return false if disabled
      #byebug
      @filters.all?{|f| evaluate_filter(f,txn,vendors,clients)}
    end 
    def modify(txn)
      return false if disabled
      actual_change = false
      @actions.each do |action|
        actual_change = true if apply_action(action,txn)
      end 
      actual_change
    end 

  end 
  class RuleEngine
    attr_accessor :rules, :vendors, :clients
    def initialize(rules, vendors, clients)
      self.rules = rules.rules.map{|r| Rule.new(r)}
      self.vendors = vendors
      self.clients = clients
    end

    def run(transactions)
      current_set = transactions
      next_set = []
      max_iterations = 5
      max_iterations.times do |i|
        break if current_set.empty?
        next_set = current_set.select{|t| modify_txn(t)}
        puts "#{next_set.length} of #{current_set.length} transactions modified. Rule count = #{rules.length}"
        current_set = next_set
      end
    end 
    def modify_txn(t)
      modified = false
      rules.each do |r| 
        if r.matches?(t, vendors, clients)
          modified = r.modify(t) 
        end 
      end 
      modified
    end 

  end 
end 