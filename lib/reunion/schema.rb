module Reunion

  class Schema
    attr_accessor :fields

    #Ony 'enforce' fields checked
    def is_broken?(row)
      fields.any?{|pair| pair[1].critical && !pair[1].validate(row[pair[0]]).nil?}
    end  

    def validate(row)
      results = {}
      fields.to_a do |pair|
        pair[1].validate(row[pair[0]])
      end.compact
    end 

    def normalize(row)
      fields.each_pair do |k,v|
        row[k] = v.normalize(row[k])
      end
    end 

    def initialize(fields = {})
      @fields = fields
    end

    def [](key)
      @fields[key]
    end
  end 


  class StatementSchema < Schema
    def initialize(fields = {})
      @fields = {date: DateField.new(readonly:true, critical:true), 
                 balance: AmountField.new(readonly:true, critical:true)}.merge(fields)
    end
  end

  class SchemaMethodDefinition
    def initialize(name, example, lambda_generator, &block)
      @name = name
      @lambda_generator = lambda_generator
      @example = example
      block.call(self) if block_given?
    end 
    attr_accessor :name, :lambda_generator, :example
  end 
  class TransactionSchema < Schema

    def initialize(fields = {})
      @fields = {id: StringField.new(readonly: true),
                 date: DateField.new(readonly: true, critical:true), 
                 amount: AmountField.new(readonly: true, critical:true),
                 balance_after: AmountField.new(readonly: true),
                 tags: TagsField.new,
                 vendor: SymbolField.new,
                 vendor_description: DescriptionField.new,
                 vendor_tags: TagsField.new,
                 description: DescriptionField.new(readonly: true),
                 account_sym: SymbolField.new(readonly: true),
                 transfer: BoolField.new,
                 discard_if_unmerged: BoolField.new(readonly: true),
                 currency: UppercaseSymbolField.new(readonly: true)
                }.merge(fields)
    end

  end 

  class SchemaField
    def initialize(readonly: false, critical: false)
      @readonly = readonly
      @critical = critical
    end 
    def normalize(value)
      value
    end

    attr_accessor :allowed_values, :value_required, :readonly, :critical

    def validate(value)
      if allowed_values
        return "Value #{value.inspect} not one of allowed values #{allowed_values.inspect}" unless allowed_values.include? value
      end
      if value_required && value.nil?
        return "Value required"
      end 
      nil
    end

    def format(value)
      value.to_s
    end

    def merge(oldvalue,newvalue)
      newvalue
    end

    def query_methods
      [SchemaMethodDefinition.new(:compare, "[either,or]|compareto",
         ->(args){
          expected = args.flatten
          if expected.length == 1
            expected = expected.first
            return expected.respond_to?(:call) ? expected : ->(v){v == expected}
          else
            return ->(v){expected.include?(v)}
          end 
        })]
    end 

  end 



  class SymbolField < SchemaField
    def self.to_symbol(value)
      return nil if value.nil?
      str = value.to_s.strip.squeeze(" ").downcase.gsub(" ","_")
      return nil if str.empty?
      str.to_sym
    end
    def normalize(value)
      SymbolField.to_symbol(value)
    end

  end

  class UppercaseSymbolField < SymbolField
    def normalize(value)
      return nil if value.nil?
      str = value.to_s.strip.squeeze(" ").upcase.gsub(" ","_")
      return nil if str.empty?
      str.to_sym
    end
  end 


  class TagsField < SchemaField

    def normalize(value)
      [value].flatten.map{|v| SymbolField.to_symbol(v)}.compact.uniq
    end 
    def validate(value)
      if allowed_values
        invalid = value - allowed_values
        return "Values #{invalid.inspect} not found in allowed values #{allowed_values.inspect}" unless invalid.empty?
      end
      if value_required && value.empty?
        return "Value required"
      end 
      nil
    end 

    def merge (oldvalue, newvalue)
      [oldvalue,newvalue].flatten.compact.uniq
    end

    def query_methods
      [SchemaMethodDefinition.new(:compare, "[either,or]|compareto",
         ->(args){
          expected = args.flatten
          if expected.length == 1
            expected = expected.first
            return expected.respond_to?(:call) ? ->(v){ v.any?(&expected)} : ->(v){v.include?(expected)}
          else
            return ->(v){!(expected & v).empty?}
          end 
        })]
    end 

  end 




  class BoolField < SchemaField
    def normalize(value)
      nval = value
      return nil if nval.nil?
      if nval.is_a?(String)
        return nil if nval.empty? || nval.strip.empty?
        nval = nval.strip.downcase.to_sym
      end

      if nval.is_a?(Symbol)
        return true if [:y, :yes, :true, :on, :'1'].include? nval
        return false if [:n, :no, :false, :off, :'0'].include? nval
      end 
      return value
    end

    def validate(value)
      unless value.nil? || value.is_a?(FalseClass) || value.is_a?(TrueClass)
        return "Value #{value.inspect} (#{value.class.name}) is not TrueClass, FalseClass, or nil"
      end
      if value_required && value.nil?
        return "Value required"
      end 
      nil
    end

    def query_methods
      [SchemaMethodDefinition.new(:compare, "[either,or]|compareto",
         ->(args){
          expected = args.first.nil? ? true : args.first
          ->(v){v == expected}
        })]
    end 
  end 


  class AmountField < SchemaField
    def normalize(value)
      return 0 if value.nil?
      if value.is_a?(String)
        return 0 if value.empty?
        return BigDecimal.new(value.gsub(/[\$,]/, ""))
      end
      value
    end

    def format(value)
      "%.2f" % value
    end

    def query_methods
      [SchemaMethodDefinition.new(:compare, "[20.00,2.00]|5.00",
         ->(args){
          expected = args.flatten
          if expected.length == 1
            expected = expected.first
            return expected.respond_to?(:call) ? expected : ->(v){v == expected}
          else
            return ->(v){expected.include?(v)}
          end 
        }),
      SchemaMethodDefinition.new(:above, "5.00",
         ->(args){
          expected = args.first
          ->(v){v > expected}
        }),
      SchemaMethodDefinition.new(:below, "5.00",
         ->(args){
          expected = args.first
          ->(v){v < expected}
        }),
      SchemaMethodDefinition.new(:between, "5.00",
         ->(args){
          low = args.min
          high = args.max
          ->(v){v >= low && v <= high}
        })
      ]
    end 
  end

  class DateField < SchemaField
    def normalize(value)
      value.is_a?(String) ? Date.parse(value) : value
    end

    def format(value)
      value.strftime("%Y-%m-%d")
    end
    def validate(value)
      return "Date required. Found nil" if value_required && value.nil?
      return "Value #{value.inspect} is not a valid date" unless value.is_a?(Date)
      nil
    end

    def query_methods
      to_date_mjd = lambda do |v|
        v = Date.parse(v) if v.is_a?(String)
        raise "Invalid date #{v.inspect}" unless v.is_a?(Date)
        v.mjd
      end
      [SchemaMethodDefinition.new(:year, "[2013,2014]|2012",
         ->(args){
          expected = args.flatten
          if expected.length == 1
            expected = expected.first
            if expected.respond_to? :call 
              expected
            else
              expected = Integer(expected)
              ->(v){v.year == expected}
            end
          else
            expected = expected.map{|v| Integer(v)}
            ->(v){expected.include?(v.year)}
          end
        }),
        SchemaMethodDefinition.new(:compare, "['2012-04-01','2013-04-02']|Date.today|'2011-01-01'",
         ->(args){
          expected = args.flatten.map{|v| v.is_a?(String) ? Date.parse(v).mjd : v.is_a?(Date) ? v.mjd : v}
          raise "Invalid date arguments" if expected.any?{|v| !v.respond_to?(:call) && !v.is_a?(Numeric)}
          if expected.length == 1
            expected = expected.first
            return expected.respond_to?(:call) ? expected : ->(v){v.mjd == expected}
          else
            return ->(v){expected.include?(v.mjd)}
          end 
        }),
      SchemaMethodDefinition.new(:after, "'2011-9-11'",
         ->(args){
          expected = to_date_mjd.call(args.first)
          ->(v){v.mjd > expected}
        }),
      SchemaMethodDefinition.new(:before, "'1965-01-01'",
         ->(args){
          expected = to_date_mjd.call(args.first)
          ->(v){v.mjd < expected}
        }),
      SchemaMethodDefinition.new(:between, "2011-01-01,2012-01-01",
         ->(args){
          args = args.flatten.map(&to_date_mjd)
          low = args.min
          high = args.max
          ->(v){v.mjd >= low && v.mjd <= high}
        })
      ]
    end 

  end

  class StringField < SchemaField
    def normalize(value)
      value.to_s.strip
    end


    def query_methods
      [SchemaMethodDefinition.new(:compare, "'case-insensitve-match'|/regexp/i|'^prefix'|['multiple','matches',/andregexps/i]",
         ->(args){
          expected = args.flatten
          lambda do |value|
            expected.any? do |query|
              case
              when query.is_a?(Regexp) 
                query.match(value) 
              when query.is_a?(String) && query.start_with?("^")
                value.downcase.start_with?(query[1..-1].downcase)
              when query.is_a?(String) && query.length > 0 
                query.casecmp(value) == 0
              when query.respond_to?(:call) 
                query.call(value)
              else
                raise "Unknown query type #{query.class}"
                false
              end
            end
          end 
        })]
    end 
  end

  class DescriptionField < StringField
    def normalize(value)
      value.nil? ? nil : value.to_s.squeeze(" ").strip
    end
  end

end

