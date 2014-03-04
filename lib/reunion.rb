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

require 'reunion/transaction'
require 'reunion/account'
require 'reunion/input_file'
require 'reunion/parsers'
require 'reunion/standard_convention'
require 'reunion/account_merge'
require 'reunion/account_reconcile'
require 'reunion/expectations'


require 'reunion/output'
require 'reunion/transfers'
require 'reunion/rules'

require 'reunion/vendors'