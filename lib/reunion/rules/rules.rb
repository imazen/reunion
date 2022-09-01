module Reunion

  class RuleExpressionType

    def initialize(smd: nil, &block)
      @example = smd.nil? ? "" : smd.example
      @aliases = []
      @kind = :filter
      @exclude = false
      @field = nil
      @name = nil
      @schema_method_definition = smd

      block.call(self) if block_given?
    end 

    attr_accessor :name, :example, :aliases, :field, :schema_method_definition, :exclude, :kind, :apply_action
    
    def all_names
      [name, aliases].flatten.compact.uniq
    end

    def with_name(name)
      @name = name
      self
    end

    def with_aliases(aliases)
      @aliases += [aliases].flatten
      self
    end 
    def with_field(field)
      @field = field
      self
    end

    def with_exclude(exclude)
      @exclude = exclude
      self
    end 

    def clone
      r = super
      r.aliases = r.aliases.clone
      r
    end 
  end 


  class RuleSyntaxDefinition

    def initialize(schema)
      @list = []
      @schema = schema
    end 

    attr_accessor :schema, :list

    def add_all_and_none
      list << RuleExpressionType.new(smd: SchemaMethodDefinition.none).with_name(:none)
      list << RuleExpressionType.new(smd: SchemaMethodDefinition.all).with_name(:all)
      self
    end

    def add_txn_lambdas
      list << RuleExpressionType.new(smd: SchemaMethodDefinition.txn_lambda).with_name(:for_transactions)
      list << RuleExpressionType.new(smd: SchemaMethodDefinition.txn_lambda).with_name(:exclude_transactions).with_exclude(true)
      self
    end

    def add_query_methods
      schema.fields.each_pair do |k,v|
        v.query_methods.each do |smd|
          smd.name ||= :compare

          #If there is an equivalent set method, don't support the singular form as a query method
          nouns = [k.to_s.gsub(/s\Z/i,"") + "s", v.readonly ? k.to_s : nil].compact
          nouns = nouns.map{|noun|"#{noun}_#{smd.name}"} unless smd.name == :compare

          #Copy basics from SchemaMethodDefinition
          query = RuleExpressionType.new(smd: smd){ |t|
            t.field = k
          }

          #Make a copy for the 'exclude version'
          exclude = query.clone.with_exclude(true)
          
          query.with_aliases(nouns.map{|noun| "for_#{noun}".to_sym})
          query.with_aliases(nouns.map(&:to_sym))
          query.with_aliases(nouns.map{|noun| "when_#{noun}".to_sym})

          exclude.with_aliases(nouns.map{|noun| "exclude_#{noun}".to_sym})

          list << query
          list << exclude
        end
      end
      self
    end

    def add_action_methods
      schema.fields.each_pair do |k,v|
        if !v.readonly
          action = RuleExpressionType.new{|p|
            p.apply_action = -> (txn, args){

              args = v.is_a?(TagsField) ? args.flatten : args.first
              old_value = txn[k]
              new_value = v.merge(old_value, args)
              changed = old_value != new_value
              txn[k] = new_value if changed
              changed
            }
            name = v.is_a?(TagsField) ? k.to_s.gsub(/s\Z/i,"") : k.to_s
            p.with_aliases(["set", "use"].map{|verb| "#{verb}_#{name}".to_sym} + [name.to_sym])

            p.name = "set_#{name}".to_sym
            p.field = k
            p.kind = :action
          }
          list << action
        end 
      end
      self
    end

    def add_aliases
      aliases = {
        as_transfer: :set_transfer, 
        year: :for_date_year, 
        before: :for_date_before, 
        after: :for_date_after, 
        matches: :for_descriptions, 
        match: :for_descriptions, 
        for_match: :for_descriptions, 
        for_matches: :for_descriptions, 
        exclude: :exclude_transactions, 
        :for => :for_transactions,
        transactions: :for_transactions}

      aliases.each_pair do |a, existing|
        method = list.find{|e| e.all_names.include?(existing)}
        raise "No method #{existing} found" if method.nil?
        method.with_aliases(a)
      end
      self
    end

    def compute_lookup_table
      not_sym = list.map{|e| e.all_names}.flatten.select{|v| !v.is_a?(Symbol)}
      raise ("method aliases not a symbol: " + not_sym * " ") if not_sym.count > 0
      lookup = Hash[list.flat_map{|e| e.all_names.map{|name| [name.to_sym,e]}}]
      lookup
    end 

  end 

  class StandardRuleSyntax < RuleSyntaxDefinition
    def initialize(schema)
      super(schema)
      add_all_and_none
      add_txn_lambdas
      add_query_methods
      add_action_methods
      add_aliases
    end  
  end


  class Rules

    def initialize(syntax, stack = nil, parent = nil, block_scope = nil)
      @syntax = syntax
      @block_scope = block_scope.nil? ? (stack.nil? && parent.nil?) : block_scope
      @parent = parent
      @children = []
      @stack = stack || []
      @rules = []
      @searcher = nil
      @subtree_rules_added = 0
      @block_result_handler = nil 
    end

    def rule_methods
      @syntax_lookup_table ||= syntax.compute_lookup_table
    end

    attr_reader :rules, :syntax
    attr_accessor :block_scope
    attr_accessor :subtree_rules_added 

    def inspect
      output = ""
      rules.each do |r|
        output << r.map{|h| {name: h[:name], arguments: h[:arguments] }}.inspect
        output << "\n"
      end
      output
    end


    def block_result_handler
      @block_result_handler || (@parent.nil? ? nil : @parent.block_result_handler) || :add_default_hash
    end 

    def add(hash = nil, &block)
      self.send(block_result_handler, hash) unless hash.nil? 
      block_returns = self.instance_eval(&block) unless block.nil?
      self.send(block_result_handler, block_returns) unless block.nil?
      flush(true)
    end 

    def eval_string(ruby_code)
      block_returns = self.instance_eval(ruby_code) unless ruby_code.nil?
      self.send(block_result_handler, block_returns) unless ruby_code.nil?
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

          r = r.add_rule_part(:for_description, q) unless q.nil?
          r = r.add_rule_part(:"set_#{prefix}_description", d) unless d.nil?
          r = r.add_rule_part(:"set_#{prefix}_tag", d) unless f.nil?
        else
          r = r.add_rule_part(:for_description, value)
        end 
        flush(true)
 
      end 
    end 


    def respond_to?(method_name)
      rule_methods.has_key?(method_name.to_sym) || super(method_name)
    end 
    def method_missing(meth, *args, &block)
      if rule_methods.has_key?(meth)
        add_rule_part(meth, *args, &block)
      else
        super(meth, *args, &block)
      end
    end

    def methods_used
      rules.map{|chain| chain.map{|r| r[:definition]}}.flatten.uniq
    end

    def add_rule_part(method, *args, &block)
      type = rule_methods[method.to_sym]
      raise "Unrecognized method #{method}; must be one of #{rule_methods.keys * ' '}" if type.nil?

      conditions = type.kind == :action ? nil : type.schema_method_definition.build.call(type.field, args)
      conditions = Re::Not(conditions) if type.exclude

      part = {name: method, 
              arguments: args, 
              stacktrace: caller(2),
              definition: type,
              is_action: type.kind == :action,
              is_filter: type.kind == :filter,
              conditions: conditions}
  
      
      flush(false) if block_scope
      newstack = @stack + [part]
      child_scope = Rules.new(syntax, newstack, self, !block.nil?)
      @children << child_scope

      #if block is specified, it's just part of a chain, not an endpoint
      if block
        #begin
        _ = child_scope.add(&block)
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
  end

end 