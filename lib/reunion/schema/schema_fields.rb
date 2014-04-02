module Reunion
  class SchemaField
    def initialize(readonly: false, critical: false, default_value: nil, display_tags: [])
      @default_value = default_value
      @readonly = readonly
      @critical = critical
      @display_tags = display_tags
    end 
    def normalize(value)
      value
    end

    def validate
      nil
    end 

    attr_accessor :allowed_values, :value_required, :readonly, :critical, :default_value, :display_tags

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
      newvalue.nil? ? oldvalue : newvalue
    end

   def query_methods
      [SchemaMethodDefinition.new(
        schema_field: self,
        build: ->(field, args){
          Re::Or.new(args.flatten.map{|arg| arg.respond_to?(:call) ? Re::Cond.new(field, :lambda, arg) : Re::Cond.new(field, :eq, normalize(arg)) })
        })]
    end 
  end 



  class SymbolField < SchemaField

    def validate(value)
      unless value.nil? || value.is_a?(Symbol)
        return "Value #{value.inspect} (#{value.class.name}) is not a Symbol"
      end
      if value_required && value.nil?
        return "Value required"
      end 
      nil
    end 

    def self.to_symbol(value, default_value = nil)
      return default_value if value.nil?
      str = value.to_s.strip.squeeze(" ").downcase.gsub(" ","_")
      return default_value if str.empty?
      str.to_sym
    end
    def normalize(value)
      SymbolField.to_symbol(value,default_value)
    end

  end

  class UppercaseSymbolField < SymbolField
    def normalize(value)
      return default_value if value.nil?
      str = value.to_s.strip.squeeze(" ").upcase.gsub(" ","_")
      return default_value if str.empty?
      str.to_sym
    end
  end 


  class TagsField < SchemaField

    def normalize(value)
      [value].flatten.map{|v| SymbolField.to_symbol(v)}.compact.uniq
    end 


    def validate(value)
      if !value.nil? && !value.is_a?(Array)
        return "Value must be an array"
      end 
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
      [SchemaMethodDefinition.new(
        schema_field: self,
        build: ->(field, args){
          Re::Or.new(args.flatten.map{|arg| arg.respond_to?(:call) ? Re::Cond.new(field, :lambda, arg) : Re::Cond.new(field, :include, SymbolField.to_symbol(arg)) })
        })]
    end 

  end 




  class BoolField < SchemaField
    def normalize(value)
      nval = value
      return default_value if nval.nil?
      if nval.is_a?(String)
        return default_value if nval.empty? || nval.strip.empty?
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
      [SchemaMethodDefinition.new(
        schema_field: self,
        build: ->(field, args){
          expected = args.first.nil? ? true : args.first
          Re::Cond.new(field, :eq, expected)
        })]
    end 

  end 


  class AmountField < SchemaField
    def normalize(value)
      return default_value if value.nil?
      if value.is_a?(String)
        return default_value if value.empty?
        return BigDecimal.new(value.gsub(/[\$,]/, ""))
      elsif value.is_a?(Float)
        return BigDecimal.new(value, 2 + value.to_i.to_s.length)
      elsif !value.is_a?(BigDecimal)
        return BigDecimal.new(value)
      end
      value
    end

    def format(value)
      value.nil? ? "" : ("%.2f" % value)
    end

    def query_methods
      [SchemaMethodDefinition.new(
        schema_field: self,
        prep_data: ->(field, value, target){
          target[field] = value.nil? ? nil : normalize(value) 
        },
        name: :compare, example: "[20.00,2.00]|5.00",
        build: ->(field, args){
          Re::Or.new(args.flatten.map{|arg| 
            arg.respond_to?(:call) ? 
              Re::Cond.new(field, :lambda, arg) : 
              Re::Cond.new(field, :eq, normalize(arg)) })
        }),
      SchemaMethodDefinition.new(schema_field: self, name: :above, example: "5.00",
        build: ->(field, args){
          Re::Cond.new(field, args.first, :gt, normalize(arg))
        }),
      SchemaMethodDefinition.new(self, :below, "5.00",
         ->(field, args){
          Re::Cond.new(field, args.first, :lt, normalize(arg))
        }),
      SchemaMethodDefinition.new(self, :between, "5.00",
         ->(field, args){
          args = args.map{|v| normalize(v)}
          low = args.min
          high = args.max
          Re::Cond.new(field, :between_inclusive, [low, high]) 
        })
      ]
    end 
  end

  class DateField < SchemaField
    def normalize(value)
      value.is_a?(String) ? Date.parse(value) : value
    end

    def format(value)
      value.nil? ? "" : value.strftime("%Y-%m-%d")
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

      prep_mjd = lambda do |field, value, target|
            target["#{field}.mjd".to_sym] = value.nil? ? nil : to_date_mjd.call(value)
      end


      [SchemaMethodDefinition.new(schema_field: self, name: :year, example: "[2013,2014]|2012",
        prep_data: ->(field, value, target){
          target["#{field}.year".to_sym] = value.nil? ? nil : value.year 
        },
        build: ->(field, args){
          field_name = "#{field}.year".to_sym
          Re::Or.new(args.flatten.map{|arg| arg.respond_to?(:call) ? Re::Cond.new(field_name,  :lambda, arg) : Re::Cond.new(field_name, :eq, normalize(arg).year) })
        }),
        SchemaMethodDefinition.new(
         schema_field: self, name: :compare, example: "['2012-04-01','2013-04-02']|Date.today|'2011-01-01'",
          prep_data: prep_mjd,
          build: ->(field, args){
            field_name = "#{field}.mjd".to_sym
            Re::Or.new(args.flatten.map{|arg| arg.respond_to?(:call) ? Re::Cond.new(field_name,  :lambda, arg) : Re::Cond.new(field_name, :eq, to_date_mjd.call(arg)) })
          }),
      SchemaMethodDefinition.new(schema_field: self, name: :after, example: "'2011-9-11'",
        prep_data: prep_mjd,
        build: ->(field, args){
          Re::Cond.new("#{field}.mjd".to_sym, :gt, to_date_mjd.call(args.first))
        }),
      SchemaMethodDefinition.new(schema_field: self, name: :before, example: "'1965-01-01'",
        prep_data: prep_mjd,
        build: ->(field, args){
          Re::Cond.new("#{field}.mjd".to_sym, :lt, to_date_mjd.call(args.first)) 
        }),
      SchemaMethodDefinition.new(schema_field: self, name: :between,example: "2011-01-01,2012-01-01",
        prep_data: prep_mjd,
        build: ->(field, args){
          args = args.flatten.map(&to_date_mjd)
          low = args.min
          high = args.max
          Re::Cond.new("#{field}.mjd".to_sym, :between_inclusive, [low, high])
        })
      ]
    end 

  end

  class StringField < SchemaField
    def normalize(value)
      value.nil? ? default_value : value.to_s.strip
    end


    def query_methods

      norm_down = -> (val){
        val = normalize(val)
        val.nil? ? nil : val.downcase
      }
      [SchemaMethodDefinition.new(schema_field: self, name: :compare, 
        example: "'case-insensitve-match'|/regexp/i|'^prefix'|['multiple','matches',/andregexps/i]",
        prep_data: -> (field,value,target){
          target["#{field}.downcase".to_sym] = norm_down.call(value)
        },
        build: ->(field, args){
          field_name = "#{field}.downcase".to_sym
          Re::Or.new(args.flatten.map{|arg|
            if arg.is_a?(Regexp)
              Re::Cond.new(field_name, :regex, arg)
            elsif arg.respond_to?(:call)
              Re::Cond.new(field, :lambda, arg)
            else 
              arg = norm_down.call(arg)
              if arg && arg.start_with?("^")
                Re::Cond.new(field_name,:prefix, arg[1..-1])
              else
                Re::Cond.new(field_name,:eq,arg)
              end
            end
          })
        })]

    end 
  end

  class DescriptionField < StringField
    def normalize(value)
      value.nil? ? default_value : value.to_s.squeeze(" ").strip
    end
  end
end 