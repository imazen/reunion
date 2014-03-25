require 'yaml'
require 'bigdecimal'
require 'csv'
require 'date'
require 'ofx'
require 'stringio'
require 'benchmark'
require 'delegate'
require 'set'
require 'fileutils'
require 'digest/sha1'
require 'json'
require 'triez'
require 'ruby-prof'

class Array
  def stable_sort_by (&block)
      n = 0
      sort_by {|x| n+= 1; [block.call(x), n]}
  end
end
class Numeric
    def to_usd
        delimiter = ','
        separator = '.'
        parts = ("%.2f" % self).split(separator)
        parts[0].gsub!(/(\d)(?=(\d\d\d)+(?!\d))/, "\\1#{delimiter}")
        "$" + parts.join(separator)
    end
end

module Reunion
end

require 'reunion/schema/schema'
require 'reunion/parsers/parsers'
require 'reunion/rules/condition_flattener'
require 'reunion/rules/decision_tree'

require 'reunion/organization'
require 'reunion/organization_transfers'
require 'reunion/standard_file_locator'

require 'reunion/bank_account'
require 'reunion/bank_account_merge'
require 'reunion/bank_account_reconcile'

require 'reunion/input_file'

require 'reunion/transaction'
require 'reunion/overrides'
require 'reunion/rules/rules'
require 'reunion/rules/rules_engine'


require 'reunion/rules/expectations'
require 'reunion/output'
