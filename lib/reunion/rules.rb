module Reunion


  class Rules

    def initialize(stack = nil, parent = nil, block_scope = nil)
      @block_scope = block_scope.nil? ? (stack.nil? && parent.nil?) : block_scope
      @parent = parent
      @children = []
      @stack = stack || []
      @rules = []
      @searcher = nil
      @subtree_rules_added = 0
      @block_result_handler = nil 
    end

    attr_reader :rules
    attr_accessor :block_scope
    attr_accessor :subtree_rules_added 

    def block_result_handler
      @block_result_handler || (@parent.nil? ? nil : @parent.block_result_handler) || :add_default_hash
    end 

    def add(hash = nil, &block)
      self.send(block_result_handler, hash) unless hash.nil? 
      block_returns = self.instance_eval(&block) unless block.nil?
      self.send(block_result_handler, block_returns) unless block.nil?
      flush(true)
    end 

    def add_vendors(&block)

      @block_result_handler = :add_vendor_hash
      add(&block)
    end

    def add_clients(&block)
      @block_result_handler = :add_client_hash
      add(&block)
    end

    def add_default_hash(retval)
    end 

    def add_client_hash(retval)
      add_vendor_hash(retval, "client")
    end 

    def add_vendor_hash(retval, prefix = "vendor")
      
      return unless retval.is_a?(Hash)
      retval.each do |key,value|
        r = add_rule_part("set_#{prefix}",key)

        if value.is_a?(Hash)
          d = value[:description] || value[:desc] || value[:d]
          f = [value[:focus]] + [value[:focus]] + [value[:f]] + [value[:tag]] + [value[:tags]]
          f = f.flatten.uniq.compact
          q = value[:query] || value[:q]

          r = r.add_rule_part("for_match", q) unless q.nil?
          r = r.add_rule_part("set_#{prefix}_description", d) unless d.nil?
          r = r.add_rule_part("set_#{prefix}_tag", d) unless f.nil?
        else
          r = r.add_rule_part("for_match", value)
        end 
        flush(true)
 
      end 
    end 


    QUERY_NOUNS = %w{all none transfer transactions vendors clients vendor_tags client_tags vendor_descriptions client_descriptions tags tax_expenses subledgers match amount amount_over amount_under amount_between year date date_before date_after date_between}
    QUERY_VERBS = %w{for when exclude}
    ACTION_NOUNS = %w{vendor client vendor_tag client_tag vendor_description client_description subledger tax_expense as_transfer tag}
    ACTION_VERBS = %W{set use}
 
    ALIASES = {before: :for_date_before, after: :for_date_after, matches: :for_match, exclude: :exclude_transactions, :for => :for_transactions, :with_focus => :set_vendor_tag, :for_focuses => :for_vendor_tags, :focuses => :for_vendor_tags}

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
        add_rule_part(meth, *args, &block)
      else
        super(meth, *args, &block)
      end
    end


    def add_rule_part(method, *args, &block)
      name = ALIASES[method] || method
      part = parse_step_name(name).merge(
              {name: name, 
              method_name: method, 
              arguments: args, 
              stacktrace: caller(2)})

      flush(false) if block_scope
      newstack = @stack + [part]
      child_scope = Rules.new(newstack, self, !block.nil?)
      @children << child_scope

      #if block is specified, it's just part of a chain, not an endpoint
      if block
        #begin
        r = child_scope.add(&block)
        #rescue NoMethodError => e 
        #  e.set_backtrace(part[:stacktrace]) unless @exception_rethrown
        #  @exception_rethrown = true
        #  raise e
        #end 
        @exception_rethrown = false
        #Handle return value
        
        return nil
      else
        return child_scope
      end
    end 



    def add_completed_rule(stack)
      @subtree_rules_added += 1
      if @parent.nil?
        @rules << stack.clone
      else
        @parent.add_completed_rule(stack)
      end 
    end 

    def flush(raise_if_useless = false)
      @children.each{|c| c.flush(true)}
      @children.clear
      if subtree_rules_added < 1
        if block_scope
          raise "Statement failed to produce a rule" if subtree_rules_added < 1 && raise_if_useless
        else
          add_completed_rule(@stack)
        end
      end 
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

    def filters
      @filters
    end 

    def actions
      @actions
    end 

    def disabled?
      @disabled
    end 

    def evaluate_filter(f, txn)
      result = evaluate_filter_noun(f,txn)
      return f[:verb] == :exclude ? !result : result
    end 

    def to_date_mjd(value)
      value.is_a?(String) ? Date.parse(value).mjd : value.mjd
    end


    def evaluate_filter_noun(f, txn)

      noun = f[:noun]
      args = f[:arguments]

      a = args.first

      #all none transfer
      return false if noun == :none
      return true if noun == :all
      return !!txn[:transfer] if noun == :transfers

      return txn.amount == a if noun == :amount
      return txn.amount > a if noun == :amount_over
      return txn.amount < a if noun == :amount_under
      return txn.amount >= args.min && txn.amount <= args.max if noun == :amount_between


      return txn.date.year == a.is_a?(String) ? Date.parse(a).year : a.is_a?(Date) ? a.year : nil if noun == :year
      return txn.date.mjd == to_date_mjd(a) if noun == :date
      return txn.date.mjd > to_date_mjd(a) if noun == :date_after
      return txn.date.mjd < to_date_mjd(a) if noun == :date_before
      return txn.date.mjd >= args.map(&to_date_mjd).min && txn.date <= args.map(&to_date_mjd).max if noun == :date_between
      
      #transactions
      return args.first.call(txn) if noun == :transactions

    
      if [:vendors, :clients, :client_tags, :vendor_tags, :client_descriptions, :vendor_descriptions, :tags, :tax_expenses, :subledgers, :match].include? noun
        if noun == :match
          data = txn[:description]
        elsif !noun.to_s.end_with?("tags") && noun.to_s.end_with?("s")
          data = txn[noun.to_s[0..-2].to_sym]
        else
          data = txn[noun]
        end 
        return is_match(args,data,f)
      else
        raise "Unexpected filter noun #{noun}"
      end
      false
    end 

    def is_match(query_arguments, data, filter)
      a = query_arguments.flatten
      data = (data.is_a?(Array) ? data : [data]).flatten
      a.any? do |query|
        data.any? do |value|
          case
          when query.is_a?(Regexp) 
            query.match(value) 
          when query.is_a?(String) && query.start_with?("^")
            value.downcase.start_with?(query[1..-1].downcase)
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
      field_is_array = false

      if noun == :as_transfer
        arg = arg.nil? ? true : arg
        noun = :transfer
      elsif noun.to_s.end_with? "tag"
        field_is_array = true
        noun = "#{noun}s".to_sym
      end 

      if field_is_array
        txn[noun] ||= []
        actual_change = !txn[noun].include?(arg)
        txn[noun] << arg if actual_change
      else
        actual_change = txn[noun] != arg
        txn[noun] = arg
      end 

      #puts "#{action[:method_name]}(#{args * ','})" if actual_change
      actual_change
    end 
    def matches?(txn)
      return false if disabled
      #byebug
      matches = @filters.all?{|f| evaluate_filter(f,txn)}
      @matched_transactions ||= []
      @matched_transactions << txn if matches
      matches
    end

    attr_accessor :matched_transactions, :modified_transactions, :changed_transactions

    def modify(txn)
      return false if disabled
      @modified_transactions ||= []
      @changed_transactions ||= []
      @modified_transactions << txn
      actual_change = false
      @actions.each do |action|
        actual_change = true if apply_action(action,txn)
      end
      @changed_transactions << txn if actual_change
      actual_change
    end 

  end 
  class RuleEngine
    attr_accessor :rules
    def initialize(rules)
      rules.flush(true)
      @rules = rules.rules.map{|r| Rule.new(r)}
    end

    def run(transactions)
      current_set = transactions
      next_set = []
      max_iterations = 3
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
        if r.matches?(t)
          modified = r.modify(t) 
        end 
      end 
      modified
    end 

  end 
end 