require 'forwardable'
module Reunion
  class TxnBase
    extend Forwardable

    def initialize(schema: nil, from_hash: {}, **args)

      @data = from_hash.clone.merge(args)
      @data[:schema] = schema unless schema.nil?
    end 

    attr_accessor :data
    def_delegators :@data, :size, :[], :[]=, :map, :each, :hash, :eql?, :delete, :key?, :has_key?

    def self.delegated_reader( *arr )
       arr.each do |a|
        self.class_eval do
          define_method(a) do
            @data[a]
          end
        end
       end
    end

    # def [](key)
    #   @data[key]
    # end

    delegated_reader :date, :source 

    def date_str
      date.strftime("%Y-%m-%d")
    end
  end 

  class Statement < TxnBase
    delegated_reader :date, :balance
    def schema
      StatementSchema.singleton
    end 
  end 

  class Transaction < TxnBase

    delegated_reader :id, :amount, :description, :balance_after, :vendor, :client, :account_sym

    delegated_reader :transfer, :transfer_pair, :discard_if_unmerged, :priority, :schema

    def tags
      @data[:tags] ||= []
      @data[:tags]
    end 

    def merge_transaction(other)
      new_data = data.merge(other.data) do |key, oldval, newval|
        if (key == :amount || key == :date) && newval != oldval
          raise "Tried to merge two transactions with dissimilar amounts and dates"
        else
          schema[key] ? schema[key].merge(oldval,newval) : newval
        end 
      end 
      Transaction.new(from_hash: new_data)
    end

    def amount_str
      amount.nil? ? "" : ("%.2f" % amount) 
    end 

    def to_long_string
      [id, date_str, amount_str, description] * "    "
    end 


    def lookup_key_basis 
      raise "Transaction without subindex! Run subindex_all on ALL transactions" if data[:subindex].nil?
      [account_sym,date_str,amount_str,description.strip.squeeze(" ").downcase,data[:subindex].to_s] * "|"
    end 
    private :lookup_key_basis

    def lookup_key
      @lookup_key ||= Digest::SHA1.hexdigest(lookup_key_basis)
    end 


  end
end
