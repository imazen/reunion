require 'reunion/schema/schema_fields'
module Reunion

  class Schema
    attr_accessor :fields

    #Ony 'enforce' fields checked
    def is_broken?(row)
      fields.any?{|pair| pair[1].critical && !pair[1].validate(row[pair[0]]).nil?}
    end  

    def validate(row)
      results = []
      fields.each_pair do |name, field|
        result = field.validate(row[name])
        results << {field:name, field_obj: field, message: result} if result
      end
      results.empty? ? nil : results
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

  # allow keyword arguments for Structs via subclass
  class Struct < ::Struct
    def initialize(*args, **kwargs)
      param_hash = kwargs.any? ? kwargs : Hash[ members.zip(args) ]
      param_hash.each { |k,v| self[k] = v }
    end
  end



  SchemaMethodDefinition = Struct.new(:schema_field, :name, :example, :build, :prep_data) do
    def self.all
      SchemaMethodDefinition.new(nil, :all, "", ->(field, args){Re::Yes.new})
    end

    def self.none
      SchemaMethodDefinition.new(nil, :none, "", ->(field, args){Re::Not.new(Re::Yes.new)})
    end

    def self.txn_lambda
      SchemaMethodDefinition.new(nil, :none, "", ->(field, args){ Re::Cond.new(nil, :lambda, args.first)})
    end
  end
  
  class StatementSchema < Schema
    def initialize(fields = {})
      @fields = {date: DateField.new(readonly:true, critical:true), 
                 balance: AmountField.new(readonly:true, critical:true)}.merge(fields)
    end
  end

   
  class TransactionSchema < Schema
    def initialize(fields = {})
      @fields = {id: StringField.new(readonly: true),
                 date: DateField.new(readonly: true, critical:true), 
                 amount: AmountField.new(readonly: true, critical:true, default_value: 0),
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



end

