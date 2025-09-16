require 'csv'
require 'bigdecimal'
require 'date'
require 'fileutils'

module Reunion
    module Metadata
        class AmazonRetailCsvParser
          def csv_options
            {
              headers: :first_row,
              header_converters: ->(h){ h.nil? ? nil : h.encode('UTF-8').strip.downcase.gsub(/\s+/, '_').gsub(/\W+/, '').to_sym },
              liberal_parsing: true,
              quote_char: '"',
              col_sep: ','
            }

        end

          def parse_amount(text)
            return 0 if text.nil? || text.to_s.empty? || text.to_s == 'Not Available'
            BigDecimal(text.to_s.gsub(/[^0-9\.-]/, ''))
          end

          def parse_date(text)
            return nil if text.nil? || text.to_s.empty? || text.to_s == 'Not Available'
            Date.parse(text.to_s)
          end

          # Returns an array of item hashes with keys:
          # :order_id, :order_date, :ship_date, :total_owed, :subtotal, :tax, :card_text, :product_name, :asin, :order_status, :shipment_status
          def parse(text)
            safe = text.encode('UTF-8', invalid: :replace, undef: :replace)
            CSV.parse(safe, **csv_options).map do |row|
              {
                order_id: (row[:order_id] || '').strip,
                order_date: parse_date(row[:order_date]),
                ship_date: parse_date(row[:ship_date]),
                subtotal: parse_amount(row[:shipment_item_subtotal]),
                tax: parse_amount(row[:shipment_item_subtotal_tax]),
                total_owed: parse_amount(row[:total_owed]),
                owed_cents: begin v = parse_amount(row[:total_owed]); v ? (v * 100).round.to_i : nil end,
                card_text: (row[:payment_instrument_type] || '').strip,
                product_name: (row[:product_name] || '').strip,
                asin: (row[:asin] || '').strip,
                order_status: (row[:order_status] || '').strip,
                shipment_status: (row[:shipment_status] || '').strip
              }
            end
          end
        end 
        class AmazonRetailMetadataExtractor
          def initialize(schema)
            @schema = schema
          end

          def format_usd(value)
            value.nil? ? '' : ("$%.2f" % value)
          end

          def describe(items)
            items.map { |i| "#{format_usd(i[:subtotal])}: #{i[:product_name]}" }.join(" || ")
          end

          # Build candidate dates around order and ship dates, configurable via env
          # Defaults: order: -0..+4 days; ship: -2..+7 days
          def candidate_dates_for(item)
            # Prefer ship date if present, else order date
            anchor = item[:ship_date] || item[:order_date]
            return [] if anchor.nil? && item[:order_date].nil?
            dates = []
            order_pre  = (ENV['AMAZON_RETAIL_ORDER_DATE_PRE_DAYS']  || '0').to_i
            order_post = (ENV['AMAZON_RETAIL_ORDER_DATE_POST_DAYS'] || '4').to_i
            ship_pre   = (ENV['AMAZON_RETAIL_SHIP_DATE_PRE_DAYS']   || '5').to_i
            ship_post  = (ENV['AMAZON_RETAIL_SHIP_DATE_POST_DAYS']  || '5').to_i
            if item[:order_date]
              ((item[:order_date] - order_pre)..(item[:order_date] + order_post)).each { |d| dates << d }
            end
            if anchor
              ((anchor - ship_pre)..(anchor + ship_post)).each { |d| dates << d }
            end
            # remove any prior to (item[:order_date] - order_pre)
            dates = dates.select { |d| d >= (item[:order_date] - order_pre) }
            dates.compact.uniq
          end

          def build_metadata_txns(order_id:, items_subset:, amount:, dates:)
            dates.map do |date|
              Reunion::Transaction.new(
                schema: @schema,
                date: date,
                amount: -1 * amount,
                description: 'AMAZON.COM',
                description2: "Order #{order_id}: " + describe(items_subset)
              )
            end
          end
        end

        
        # For the request-my-data format
        class RetailOrderHistory

            # Shipment Item Subtotal (decimal)
            # Shipment Item Subtotal Tax  (decimal)
            # Payment Instrument Type (' and ' delimited strings, e.g. "Visa - 1234 and Gift Certificate" etc)
            # Product Name (string)
            # Order ID  (string)
            # Order Date  (YYYY-MM-DDThh:mm:ss+00:00Z format)

            # Ship Date (YYYY-MM-DDThh:mm:ss+00:00Z format)


            def initialize(org:, retail_order_history_csv_path: nil, start_date: nil, stop_date: nil, year: nil, output_folder:, last4_to_ignore: [], debug: false)
                @org = org
                @csv_path = retail_order_history_csv_path
                @output_folder = output_folder
                @last4_to_ignore = (last4_to_ignore || [])
                @debug = !!debug
                @bank_tag_to_last4s = Hash.new { |h,k| h[k] = [] }
                @bank_tag_to_label = {}
                @reuse_log = []
                @order_date_deltas = Hash.new(0)
                @ship_date_deltas = Hash.new(0)

                # Normalize dates and year
                @start_date, @stop_date = normalize_dates(start_date, stop_date, year)

                # Derive last4 and default labels from the organization's bank accounts
                (@org.bank_accounts || []).each do |acct|
                  bank_tag = acct.permanent_id
                  # Default label is the first file_tag if present; otherwise camelCased permanent_id
                  default_label = nil
                  if acct.respond_to?(:file_tags) && acct.file_tags && !acct.file_tags.empty?
                    default_label = acct.file_tags.first.to_s
                  end
                  @bank_tag_to_label[bank_tag] = default_label || camel_case_label(bank_tag)

                  if acct.respond_to?(:last4) && acct.last4.is_a?(Array)
                    acct.last4.each do |l4|
                      next if l4.nil? || l4.to_s.strip.empty?
                      @bank_tag_to_last4s[bank_tag] << l4.to_s
                    end
                  end
                end
            end

            # Normalize date inputs: accept String/Date/Integer (year), with defaults to previous calendar year
            def normalize_dates(start_date, stop_date, year)
              # If year is provided (String or Integer), it takes precedence when explicit start/stop are nil
              if (start_date.nil? && stop_date.nil?) && !year.nil?
                y = parse_year(year)
                return [Date.new(y,1,1), Date.new(y,12,31)]
              end

              sd = parse_date_flexible(start_date)
              ed = parse_date_flexible(stop_date)

              if sd.nil? && ed.nil?
                # Default to previous year
                default_year = Date.today.year - 1
                return [Date.new(default_year,1,1), Date.new(default_year,12,31)]
              end

              [sd, ed]
            end

            def parse_year(y)
              return y if y.is_a?(Integer)
              return y.to_i if y.is_a?(String) && y =~ /^\d{4}$/
              raise ArgumentError, "Invalid year: #{y.inspect} (expected Integer or 'YYYY' String)"
            end

            def parse_date_flexible(d)
              return nil if d.nil? || d == ''
              return d if d.is_a?(Date)
              return Date.parse(d.to_s)
            end

            # Resolve the CSV path for Retail.OrderHistory.1.csv
            # - If path is nil or empty, auto-discover strictly under org.root_dir/input/**/Retail.OrderHistory.1.csv
            # - If path is a directory, search within it for the file (case-insensitive)
            # - If path is a file, use it as-is
            # Errors:
            # - Raise if no candidates found
            # - Raise with a list if multiple candidates found
            def resolve_csv_path(path)
              base_input = File.expand_path('./input', @org.root_dir)
              pattern = File.join('**', 'Retail.OrderHistory.1.csv')

              candidates = nil
              if path.nil? || path.to_s.strip.empty?
                candidates = Dir.glob(File.join(base_input, pattern), File::FNM_CASEFOLD)
              else
                abs = File.expand_path(path.to_s, @org.root_dir)
                if File.directory?(abs)
                  candidates = Dir.glob(File.join(abs, pattern), File::FNM_CASEFOLD)
                else
                  return abs
                end
              end

              if candidates.nil? || candidates.empty?
                raise "Retail.OrderHistory.1.csv not found under #{base_input}. Place the file under input/ or specify retail_order_history_csv_path pointing to a file or directory under input/."
              end
              if candidates.length > 1
                list = candidates.map { |p| " - #{p}" }.join("\n")
                raise "Multiple Retail.OrderHistory.1.csv files found under #{base_input}. Please specify retail_order_history_csv_path to disambiguate.\n#{list}"
              end
              candidates.first
            end

            def parse_card_last4s(card_text)
              text = card_text.to_s.downcase
              tokens = []
              if text =~ /(visa)\s*-\s*(\d{4})/
                tokens << "visa_#{$2}"
              end
              if text =~ /(americanexpress)\s*-\s*(\d{4})/
                tokens << "american_express_#{$2}"
              end
              tokens.uniq
            end

            def camel_case_label(sym)
              parts = sym.to_s.split('_')
              parts.map! { |p| p[0].upcase + p[1..] }
              parts.join
            end

            def bank_tag_for_card(card_text)
              # Return the first bank tag whose last4 list includes any parsed last4 from the card text
              l4s = parse_card_last4s(card_text).map { |tok| tok.split('_').last }
              return nil if l4s.empty?
              @bank_tag_to_last4s.each do |bank_tag, arr|
                return bank_tag if (arr & l4s).any?
              end
              nil
            end

            def label_for_card(card_text)
              bank_tag = bank_tag_for_card(card_text)
              return 'Unknown' if bank_tag.nil?
              @bank_tag_to_label[bank_tag] || camel_case_label(bank_tag)
            end

            def aggregate
              # Prepare organization transactions
              @org.ensure_parsed!

              @csv_path = resolve_csv_path(@csv_path)

              text = IO.read(@csv_path)
              items = AmazonRetailCsvParser.new.parse(text)
              # Filter out cancelled and zero totals
              items = items.select { |i| i[:order_status] != 'Cancelled' && i[:total_owed] && i[:total_owed] > 0 }
              # Filter by date range if provided (by order_date)
              items = items.select { |i| (@start_date.nil? || (i[:order_date] && i[:order_date] >= @start_date)) && (@stop_date.nil? || (i[:order_date] && i[:order_date] <= @stop_date)) }

              # Mappings already built from org.bank_accounts in the initializer

              extractor = AmazonRetailMetadataExtractor.new(@org.schema)

              # Track usage of item rows so they don't get reused across bank transactions
              items.each { |i| i[:used] = false }
              # Dataset-level gift-card involvement stats
              dataset_items_total = items.length
              dataset_items_with_gift = items.count { |i| (i[:card_text] || '').downcase.include?('gift') }

              # Pre-index items by last4 and candidate date for fast lookup
              items_by_last4_and_date = Hash.new { |h,k| h[k] = Hash.new { |h2,k2| h2[k2] = [] } }
              # In debug mode, massively widen order/ship windows for candidate date generation
              if @debug
                saved = {
                  'AMAZON_RETAIL_ORDER_DATE_PRE_DAYS'  => ENV['AMAZON_RETAIL_ORDER_DATE_PRE_DAYS'],
                  'AMAZON_RETAIL_ORDER_DATE_POST_DAYS' => ENV['AMAZON_RETAIL_ORDER_DATE_POST_DAYS'],
                  'AMAZON_RETAIL_SHIP_DATE_PRE_DAYS'   => ENV['AMAZON_RETAIL_SHIP_DATE_PRE_DAYS'],
                  'AMAZON_RETAIL_SHIP_DATE_POST_DAYS'  => ENV['AMAZON_RETAIL_SHIP_DATE_POST_DAYS'],
                }
                begin
                  ENV['AMAZON_RETAIL_ORDER_DATE_PRE_DAYS']  = '14'
                  ENV['AMAZON_RETAIL_ORDER_DATE_POST_DAYS'] = '14'
                  ENV['AMAZON_RETAIL_SHIP_DATE_PRE_DAYS']   = '14'
                  ENV['AMAZON_RETAIL_SHIP_DATE_POST_DAYS']  = '14'
                  items.each do |i|
                    last4s = parse_card_last4s(i[:card_text]).map { |tok| tok.split('_').last }
                    dates = extractor.candidate_dates_for(i)
                    last4s.each do |l4|
                      dates.each do |d|
                        items_by_last4_and_date[l4][d] << i
                      end
                    end
                  end
                ensure
                  saved.each { |k,v| ENV[k] = v }
                end
              else
                items.each do |i|
                  last4s = parse_card_last4s(i[:card_text]).map { |tok| tok.split('_').last }
                  dates = extractor.candidate_dates_for(i)
                  last4s.each do |l4|
                    dates.each do |d|
                      items_by_last4_and_date[l4][d] << i
                    end
                  end
                end
              end

              # Helper lambdas
              amount2 = ->(v){ v.nil? ? nil : BigDecimal("%.2f" % v) }
              sum_amount2 = ->(rows){ rows.inject(BigDecimal("0")) { |s,r| s + amount2.call(r[:total_owed]) } }


              # Select relevant bank transactions
              bank_txns = @org.all_transactions.select do |t|
                t.description == 'AMAZON.COM' && t.amount < 0 &&
                  (@start_date.nil? || t.date >= @start_date) && (@stop_date.nil? || t.date <= @stop_date)
              end

              
              # Group outputs and unmatched by bank account label
              outputs = Hash.new { |h,k| h[k] = [] }
              unmatched_by_label = Hash.new { |h,k| h[k] = [] }

              range_slug = "#{@start_date.strftime('%F')}-to-#{@stop_date.strftime('%F')}"

              # Track counts for summary
              considered_by_label = Hash.new(0)
              matched_by_label = Hash.new(0)
              matched_with_fee_by_label = Hash.new(0)

              # For date delta analysis
              order_date_deltas = Hash.new(0)
              ship_date_deltas = Hash.new(0)

              start_time = Time.now
              progress_every = (ENV['AMAZON_RETAIL_PROGRESS_EVERY'] || '25').to_i
              processed = 0
              total_matched_so_far = 0

              pass_settings = [
                {
                  name: 'strict',
                  fee_cents: 30,
                  fee_percent: 0,
                  allow_cross_order_comb: false,
                  order_after_txn_days: 0,
                  ship_before_txn_days: 0,
                  ship_after_txn_days: 2,
                  match_method: :subset,
                  include_used: false
                },
                {
                  name: 'standard',
                  fee_cents: (ENV['AMAZON_RETAIL_FEE_MAX_PER_ITEM_CENTS'] || '50').to_i,
                  fee_percent: (ENV['AMAZON_RETAIL_FEE_MAX_PER_ITEM_PERCENT'] || '9').to_i,
                  allow_cross_order_comb: (ENV['AMAZON_RETAIL_ALLOW_CROSS_ORDER_COMB'] == 'true'),
                  order_after_txn_days: @debug ? 1 : (ENV['AMAZON_RETAIL_ORDER_AFTER_TXN_DAYS'] || '1').to_i,
                  ship_before_txn_days: @debug ? 14 : (ENV['AMAZON_RETAIL_SHIP_BEFORE_TXN_DAYS'] || '6').to_i,
                  ship_after_txn_days: @debug ? 32 : (ENV['AMAZON_RETAIL_SHIP_AFTER_TXN_DAYS']  || '16').to_i,
                  match_method: :subset,
                  include_used: @debug ? true : (ENV['AMAZON_RETAIL_INCLUDE_USED'] == 'true')
                },
                {
                  name: 'rewards',
                  fee_cents: 0,
                  fee_percent: (ENV['AMAZON_RETAIL_REWARDS_MAX_PERCENT'] || '25').to_i,
                  allow_cross_order_comb: true,
                  order_after_txn_days: 5,
                  ship_before_txn_days: 0,
                  ship_after_txn_days: 3,
                  match_method: :superset,
                  include_used: false
                }
              ]

              current_txns = bank_txns
              final_pass_settings = {}
              pass_settings.each_with_index do |settings, pass_index|
                final_pass_settings = settings
                next_pass_txns = []
                unmatched_by_label.clear

                current_txns.each do |txn|
                  bank_tag = txn[:account_sym]
                  label = @bank_tag_to_label[bank_tag] || camel_case_label(bank_tag)
                  considered_by_label[label] += 1 if pass_index == 0

                  last4s_for_account = @bank_tag_to_last4s[bank_tag] || []
                  if last4s_for_account.empty?
                    unmatched_by_label[label] << { txn: txn, reason: 'no_last4_mapping' } if pass_index == pass_settings.length - 1
                    next_pass_txns << txn
                    next
                  end

                  all_items = items_by_last4_and_date.values.flat_map { |d| d.values }.flatten.uniq
                  candidates = all_items.select do |i|
                    !i[:used] &&
                    (i[:order_date] && (i[:order_date] <= (txn.date + settings[:order_after_txn_days]))) &&
                    (i[:ship_date] && ((i[:ship_date] - settings[:ship_before_txn_days]) <= txn.date) && (txn.date <= (i[:ship_date] + settings[:ship_after_txn_days])))
                  end

                  if candidates.empty?
                    unmatched_by_label[label] << { txn: txn, reason: "no_candidates_#{settings[:name]}_pass" } if pass_index == pass_settings.length - 1
                    next_pass_txns << txn
                    next
                  end

                  desired_cents = (-txn.amount * 100).round
                  matched_items = nil
                  fee_or_discount = 0

                  if settings[:match_method] == :subset
                    max_fee_for_txn = [(settings[:fee_cents] * candidates.length), (desired_cents * settings[:fee_percent] / 100.0)].max.to_i
                    matched_items, fee_or_discount = find_best_subset(candidates, desired_cents, max_fee_cents: max_fee_for_txn)
                  else # :superset
                    matched_items, fee_or_discount = find_best_superset(candidates, desired_cents, max_discount_percent: settings[:fee_percent])
                  end

                  if matched_items && !matched_items.empty?
                    matched_by_label[label] += 1
                    matched_with_fee_by_label[label] += 1 if fee_or_discount > 0

                    matched_items.each { |i| i[:used] = true }

                    description = if settings[:name] == 'rewards'
                                    "(guessed) Rewards Match: " + extractor.describe(matched_items) + sprintf(" [discount=%.2f]", fee_or_discount/100.0)
                                  else
                                    desc = extractor.describe(matched_items)
                                    desc += sprintf(" [fee_adjust=%.2f]", fee_or_discount/100.0) if fee_or_discount > 0
                                    desc
                                  end

                    outputs[label] << Reunion::Transaction.new(
                      schema: @org.schema,
                      date: txn.date,
                      amount: txn.amount,
                      description: 'AMAZON.COM',
                      description2: description
                    )
                  else
                    unmatched_by_label[label] << { txn: txn, reason: "no_match_#{settings[:name]}_pass" } if pass_index == pass_settings.length - 1
                    next_pass_txns << txn
                  end
                end
                current_txns = next_pass_txns
              end

              # Write per-account files
              outputs.each do |label, txns|
                next if txns.empty?
                output = Reunion::Export.new.transactions_to_tsv(txns)
                target = File.expand_path("#{label}-amazontsv-#{range_slug}.tsv", @output_folder)
                FileUtils.mkdir_p(File.dirname(target)) unless Dir.exist?(File.dirname(target))
                File.open(target, 'w') { |f| f.write(output) }
                $stderr << "Writing #{target}\n"
              end

              # Write unmatched per-account logs with attempt details
              unmatched_by_label.each do |label, arr|
                next if arr.empty?
                log_path = File.expand_path("#{label}-amazontsv-#{range_slug}.unmatched.txt", @output_folder)
                File.open(log_path, 'w') do |f|
                  arr.each do |u|
                    t = u[:txn]
                    f << "#{t.date.strftime('%F')} #{'%.2f' % -t.amount} #{t[:account_sym]} #{u[:reason]}\n"
                    if u[:metrics]
                      m = u[:metrics]
                      gift_part = m[:gift_item_pct] ? sprintf(" gift_item_pct=%.2f", m[:gift_item_pct]) : ""
                      f << "  metrics last4s=[#{m[:last4s]*','}] pre_items=#{m[:pre_items]} pre_unused=#{m[:pre_unused]} candidates=#{m[:candidates]}#{gift_part}\n"
                    end
                    # Overview: date windows and candidate/used counts
                    # Overview: date windows and candidate/used counts from the final pass
                    order_after_txn_days = final_pass_settings[:order_after_txn_days]
                    ship_before_txn_days = final_pass_settings[:ship_before_txn_days]
                    ship_after_txn_days = final_pass_settings[:ship_after_txn_days]
                    include_used = final_pass_settings[:include_used]

                    used_excluded = nil
                    if u[:metrics]
                      used_excluded = u[:metrics][:pre_items].to_i - u[:metrics][:pre_unused].to_i
                    end
                    f << "  overview ship_window=[-#{ship_before_txn_days}..+#{ship_after_txn_days}] order_window=[0..+#{order_after_txn_days}] txn_date=#{t.date} included_candidates=#{u.dig(:metrics, :candidates) || 'nil'} excluded_used=#{used_excluded || 'nil'} include_used=#{include_used}\n"
                    # First: candidate items grouped by order
                    if u[:candidates] && !u[:candidates].empty?
                      f << "  candidates (grouped by order):\n"
                      u[:candidates].group_by { |ci| ci[:order_id] }.
                        sort_by { |oid, _| oid }.
                        each do |oid, rows|
                        tot = rows.inject(0.0) { |s, ci| s + (ci[:total_owed] || 0.0).to_f }
                        f << "    order #{oid} total=#{'%.2f' % tot}:\n"
                        rows_sorted = rows.sort_by { |ci| [ (ci[:ship_date] || ci[:order_date] || Date.new(1900,1,1)), (ci[:total_owed] || 0.0), (ci[:product_name] || '') ] }
                        rows_sorted.each do |ci|
                          f << "      #{'%.2f' % ci[:total_owed]} - ship=#{ci[:ship_date] || 'nil'} - order=#{ci[:order_date] || 'nil'} - #{ci[:order_id]} - #{ci[:product_name]}\n"
                        end
                      end
                    end
                    # Print non-best attempts only in verbose mode; always collect best attempts
                    best_attempts = []
                    verbose = (ENV['AMAZON_RETAIL_LOG_VERBOSE'] == 'true')
                    if u[:attempts]
                      u[:attempts].each do |a|
                        if a[:type] == 'best'
                          best_attempts << a
                        elsif verbose
                          if a[:type] == 'order_total'
                            diff = (a[:desired] - a[:tested_total])
                            if a[:k] && a[:k].to_i > 0 && diff > 0
                              per_item_needed = diff / a[:k].to_f
                              f << "  attempt order_total #{a[:scope]} k=#{a[:k]} tested_total=#{'%.2f' % a[:tested_total]} desired=#{'%.2f' % a[:desired]} diff=#{'%.2f' % diff} per_item_needed=#{'%.2f' % per_item_needed}\n"
                            else
                              f << "  attempt order_total #{a[:scope]} tested_total=#{'%.2f' % a[:tested_total]} desired=#{'%.2f' % a[:desired]} diff=#{'%.2f' % diff}\n"
                            end
                          elsif a[:type] == 'comb'
                            f << "  attempt comb #{a[:scope]} k=#{a[:k]} combinations=#{a[:count]}\n"
                          elsif a[:type] == 'subseq'
                            f << "  attempt subseq #{a[:scope]} window_k=#{a[:k]} windows_tested=#{a[:count]}\n"
                          end
                        end
                      end
                    end
                    if u[:potentials]
                      u[:potentials].each do |p|
                        f << "  potential #{p[:order_id]} #{p[:product_name]} (#{'%.2f' % p[:total_owed]}) on #{(p[:ship_date] || p[:order_date])}\n"
                      end
                    end
                    # Now print best combinations at the bottom
                    unless best_attempts.empty?
                      f << "  best combinations:\n"
                      best_attempts.each do |a|
                        bu_t = a[:best_under_total]; bu_d = a[:best_under_diff]; bu_k = a[:best_under_k]
                        bo_t = a[:best_over_total];  bo_d = a[:best_over_diff];  bo_k = a[:best_over_k]
                        f << "    scope=#{a[:scope]} under_total=#{bu_t ? ('%.2f' % bu_t) : 'nil'} under_diff=#{bu_d ? ('%.2f' % bu_d) : 'nil'} k=#{bu_k || 'nil'}"
                        f << " over_total=#{bo_t ? ('%.2f' % bo_t) : 'nil'} over_diff=#{bo_d ? ('%.2f' % bo_d) : 'nil'} k=#{bo_k || 'nil'}\n"
                        # Single-line combo summaries (optional)
                        singleline = (ENV['AMAZON_RETAIL_LOG_SINGLELINE_COMBO'] == 'true')
                        if bu_t && a[:best_under_set] && !a[:best_under_set].empty?
                          set = a[:best_under_set]
                          sum_cents = set.inject(0) { |s, i| s + (i[:owed_cents] || (i[:total_owed] ? (i[:total_owed] * 100).round : 0)) }
                          k = set.length
                          up_to = (sum_cents + settings[:fee_cents] * k) / 100.0
                          parts = set.map { |i| "#{'%.2f' % i[:total_owed]}" }
                          desired = -t.amount
                          diff = desired - (sum_cents / 100.0)
                          if singleline
                            status = diff >= 0 ? "under by #{'%.2f' % diff}" : "over by #{'%.2f' % -diff}"
                            f << "    best_under: (#{parts.join(' + ')}) = #{'%.2f' % (sum_cents/100.0)} ... #{'%.2f' % up_to} [#{status}] (per_item<=#{'%.2f' % (settings[:fee_cents]/100.0)})\n"
                          end
                          # Detailed list
                          parts_line = "(#{parts.join(' + ')}) = #{'%.2f' % (sum_cents/100.0)}"
                          f << "    best_under combo k=#{k}: #{parts_line}\n"
                          set.each do |i|
                            f << "      #{'%.2f' % i[:total_owed]} - ship=#{i[:ship_date] || 'nil'} - order=#{i[:order_date] || 'nil'} - #{i[:order_id]} - #{i[:product_name]}\n"
                          end
                        end
                        if bo_t && a[:best_over_set] && !a[:best_over_set].empty?
                          set = a[:best_over_set]
                          sum_cents = set.inject(0) { |s, i| s + (i[:owed_cents] || (i[:total_owed] ? (i[:total_owed] * 100).round : 0)) }
                          k = set.length
                          parts = set.map { |i| "#{'%.2f' % i[:total_owed]}" }
                          desired = -t.amount
                          diff = desired - (sum_cents / 100.0)
                          if singleline
                            status = diff >= 0 ? "under by #{'%.2f' % diff}" : "over by #{'%.2f' % -diff}"
                            f << "    best_over: (#{parts.join(' + ')}) = #{'%.2f' % (sum_cents/100.0)} [#{status}]\n"
                          end
                          parts_line = "(#{parts.join(' + ')}) = #{'%.2f' % (sum_cents/100.0)}"
                          f << "    best_over combo k=#{k}: #{parts_line}\n"
                          set.each do |i|
                            f << "      #{'%.2f' % i[:total_owed]} - ship=#{i[:ship_date] || 'nil'} - order=#{i[:order_date] || 'nil'} - #{i[:order_id]} - #{i[:product_name]}\n"
                          end
                        end
                        # Suggest fee per item if applicable
                        if a[:best_under_diff]
                          per_item = a[:best_under_per_item_needed]
                          if per_item
                            f << "    suggest fee_max_per_item>=#{'%.2f' % per_item} (missing=#{'%.2f' % a[:best_under_diff]}, k=#{a[:best_under_k] || (a[:best_under_set] ? a[:best_under_set].length : 'nil')}) to capture best-under candidate\n"
                          end
                        end
                      end
                    end
                  end
                end
                $stderr << "Unmatched log written to #{log_path}\n"
              end

              # Console summary
              total_considered = considered_by_label.values.inject(0, :+)
              total_matched = matched_by_label.values.inject(0, :+)
              total_fee_adjusted = matched_with_fee_by_label.values.inject(0, :+)
              total_unmatched = total_considered - total_matched
              rate = total_considered.zero? ? 0.0 : (100.0 * total_matched / total_considered)
              $stdout << "\nAmazonRetail summary (#{range_slug}):\n"
              if @reuse_log.any?
                $stdout << "  WARNING: #{@reuse_log.length} transactions were matched using reused items. See amazon_reuse.log.txt for details.\n"
                log_path = File.expand_path("amazon_reuse.log.txt", @output_folder)
                File.open(log_path, 'w') do |f|
                  @reuse_log.each do |entry|
                    txn = entry[:txn]
                    f << "Bank Transaction: #{txn.date} | #{'%.2f' % txn.amount} | #{txn.description} | #{txn.account_sym}\n"
                    f << "  Matched with #{entry[:all_matched].count} items:\n"
                    entry[:all_matched].each do |item|
                      status = item[:used] ? "(REUSED)" : "(new)"
                      f << "    - #{'%.2f' % item[:total_owed]} | #{item[:order_id]} | #{item[:product_name]} #{status}\n"
                    end
                    f << "---\n"
                  end
                end
              end
              $stdout << sprintf("Overall: considered=%d matched=%d unmatched=%d match_rate=%.1f%% fee_adjusted=%d (per_item<= %.2f)\n", total_considered, total_matched, total_unmatched, rate, total_fee_adjusted, final_pass_settings[:fee_cents]/100.0)
              gift_pct_total = dataset_items_total.zero? ? 0.0 : (100.0 * dataset_items_with_gift.to_f / dataset_items_total)
              $stdout << sprintf("Gift-card involvement: items_with_gift=%d of %d (%.1f%%)\n", dataset_items_with_gift, dataset_items_total, gift_pct_total)

              # Report unmapped cards
              all_card_texts = items.map { |i| i[:card_text] }.uniq.compact
              unmapped_cards = all_card_texts.select do |card_text|
                is_unmapped = bank_tag_for_card(card_text).nil?
                is_generic = card_text.downcase.include?('gift') || card_text == 'Not Available'
                is_unmapped && !is_generic
              end

              if unmapped_cards.any?
                $stdout << "\nUnmapped Payment Instruments Found:\n"
                unmapped_cards.sort.each do |card|
                  $stdout << "  - #{card}\n"
                end
                $stdout << "\n"
              end

              (considered_by_label.keys | matched_by_label.keys | unmatched_by_label.keys).sort.each do |label|
                c = considered_by_label[label]
                m = matched_by_label[label]
                u = c - m
                pr = c.zero? ? 0.0 : (100.0 * m / c)
                # Reason breakdown
                rc = Hash.new(0)
                (unmatched_by_label[label] || []).each { |x| rc[x[:reason]] += 1 }
                reasons = rc.map { |k,v| "#{k}=#{v}" }.join(", ")
                rc_str = rc.keys.sort.map { |k| "#{k}=#{rc[k]}" }.join(' ')
                $stdout << sprintf("  %-15s: considered=%d matched=%d unmatched=%d match_rate=%.1f%% fee_adjusted=%d (%s)\n", label, c, m, u, pr, matched_with_fee_by_label[label], rc_str)
              end

              $stdout << "\nDate Delta Histograms (txn_date - item_date):\n"
              unless @order_date_deltas.empty?
                $stdout << "  Order Date Deltas (days):\n"
                @order_date_deltas.keys.sort.each do |delta|
                  $stdout << "    #{delta}: #{@order_date_deltas[delta]}\n"
                end
              end
              unless @ship_date_deltas.empty?
                $stdout << "  Ship Date Deltas (days):\n"
                @ship_date_deltas.keys.sort.each do |delta|
                  $stdout << "    #{delta}: #{@ship_date_deltas[delta]}\n"
                end
              end
            end

            def find_best_superset(items, desired_cents, max_discount_percent: 0)
              # Find the smallest combination of items that is *greater* than desired_cents,
              # but within the discount percentage.
              max_discount_cents = (desired_cents * max_discount_percent / 100.0).to_i
              
              arr = items.sort_by { |i| i[:owed_cents] || 0 }

              best_set = nil
              best_discount = nil

              (1..[arr.length, 5].min).each do |k|
                arr.combination(k).each do |set|
                  total_cents = set.inject(0) { |s, i| s + (i[:owed_cents] || 0) }
                  discount = total_cents - desired_cents

                  if discount > 0 && discount <= max_discount_cents
                    if best_discount.nil? || discount < best_discount
                      best_discount = discount
                      best_set = set
                    end
                  end
                end
                # If we found a good match at this k, we can stop. 
                # Smaller combinations are better.
                return [best_set, best_discount] if best_set
              end

              [best_set, best_discount]
            end

            def add_result(txn, desired_cents, description, order_id, items)
              # This is a placeholder for a method that would add the transaction to the results.
              # In the actual implementation, this would likely add to the `outputs` hash.
            end

            # Find the best subset with minimal positive fee difference (<= max_fee_cents), preferring exact (0 diff)
            def find_best_subset(items, desired_cents, max_fee_cents: 0, attempts: nil, scope: nil)
              items = items.reject { |i| i[:owed_cents].nil? }
              return [nil, nil] if items.empty?

              arr = items.sort_by { |i| [(i[:ship_date] || i[:order_date] || Date.new(1900,1,1)), i[:order_id], i[:asin]] }
              best_subset = nil
              best_fee = nil
              # Track best-under and best-over by absolute diff for diagnostics
              best_under = { total: nil, diff: nil, k: nil }
              best_over  = { total: nil, diff: nil, k: nil }
              best_under_set = nil
              best_over_set  = nil

              # Contiguous windows first (stability)
              (1..[5, arr.length].min).each do |k|
                window_count = 0
                0.upto(arr.length - k) do |start|
                  seq = arr[start, k]
                  total_cents = seq.inject(0) { |s, i| s + (i[:owed_cents] || 0) }
                  window_count += 1
                  diff = desired_cents - total_cents
                  if diff == 0
                    attempts << { type: 'subseq', scope: scope, k: k, count: window_count } if attempts
                    return [seq, 0]
                  elsif diff > 0 && diff <= max_fee_cents
                    if best_fee.nil? || diff < best_fee
                      best_subset = seq
                      best_fee = diff
                    end
                  end
                  # Track best under/over regardless of tolerance
                  if diff > 0 # under
                    if best_under[:diff].nil? || diff < best_under[:diff]
                      best_under[:diff] = diff
                      best_under[:total] = total_cents
                      best_under[:k] = k
                      best_under_set = seq
                    end
                  elsif diff < 0 # over
                    over = -diff
                    if best_over[:diff].nil? || over < best_over[:diff]
                      best_over[:diff] = over
                      best_over[:total] = total_cents
                      best_over[:k] = k
                      best_over_set = seq
                    end
                  end
                end
                attempts << { type: 'subseq', scope: scope, k: k, count: window_count } if attempts
              end

              # Combinations next with guards
              n = arr.length
              max_k = (ENV['AMAZON_RETAIL_MAX_K'] || '20').to_i
              max_comb = (ENV['AMAZON_RETAIL_MAX_COMB'] || '100000').to_i
              (1..[n, max_k].min).each do |k|
                comb_count = n >= k ? (1..n).inject(1, :*) / ((1..(n-k)).inject(1, :*) * (1..k).inject(1, :*)) : 0
                attempts << { type: 'comb', scope: scope, k: k, count: comb_count } if attempts
                break if comb_count > max_comb
                arr.combination(k) do |set|
                  total_cents = set.inject(0) { |s, i| s + (i[:owed_cents] || 0) }
                  fee = desired_cents - total_cents
                  # Skip if the fee is negative (over) or exceeds the max allowed fee
                  next if fee < 0 || fee > max_fee_cents
                  if best_fee.nil? || fee < best_fee
                    best_subset = set
                    best_fee = fee
                  end
                  # Track best under/over regardless of tolerance
                  if fee > 0 # under
                    if best_under[:diff].nil? || fee < best_under[:diff]
                      best_under[:diff] = fee
                      best_under[:total] = total_cents
                      best_under[:k] = k
                      best_under_set = set
                    end
                  end
                end
              end
              # Emit a summary attempt line for diagnostics
              if attempts
                attempts << {
                  type: 'best', scope: scope,
                  best_under_total: (best_under[:total] ? best_under[:total] / 100.0 : nil),
                  best_under_diff: (best_under[:diff] ? best_under[:diff] / 100.0 : nil),
                  best_under_k: best_under[:k],
                  best_under_per_item_needed: (best_under[:diff] && best_under[:k] && best_under[:k] > 0 ? (best_under[:diff] / 100.0) / best_under[:k] : nil),
                  best_over_total: (best_over[:total] ? best_over[:total] / 100.0 : nil),
                  best_over_diff: (best_over[:diff] ? best_over[:diff] / 100.0 : nil),
                  best_over_k: best_over[:k],
                  best_under_set: best_under_set,
                  best_over_set: best_over_set
                }
              end

              [best_subset, best_fee]
            end

            # Combination finder for matching items to a desired sum of :total_owed
            def find_subset(items, desired_cents, fee_max_cents: 0, attempts: nil, scope: nil)
              items = items.reject { |i| i[:owed_cents].nil? }
              return nil if items.empty?

              # Try contiguous windows by date (stability) up to len 5
              arr = items.sort_by { |i| [(i[:ship_date] || i[:order_date] || Date.new(1900,1,1)), i[:order_id], i[:asin]] }
              (1..[5, arr.length].min).each do |k|
                window_count = 0
                0.upto(arr.length - k) do |start|
                  seq = arr[start, k]
                  total_cents = seq.inject(0) { |s, i| s + (i[:owed_cents] || 0) }
                  window_count += 1
                  if total_cents == desired_cents || (desired_cents > total_cents && (desired_cents - total_cents) <= fee_max_cents)
                    attempts << { type: 'subseq', scope: scope, k: k, count: window_count } if attempts
                    return seq
                  end
                end
                attempts << { type: 'subseq', scope: scope, k: k, count: window_count } if attempts
              end

              # Then combinations up to a reasonable limit
              n = arr.length
              max_k = (ENV['AMAZON_RETAIL_MAX_K'] || '8').to_i
              max_comb = (ENV['AMAZON_RETAIL_MAX_COMB'] || '100000').to_i
              (1..[n, max_k].min).each do |k|
                comb_count = n >= k ? (1..n).inject(1, :*) / ((1..(n-k)).inject(1, :*) * (1..k).inject(1, :*)) : 0
                attempts << { type: 'comb', scope: scope, k: k, count: comb_count } if attempts
                return nil if comb_count > max_comb
                arr.combination(k) do |set|
                  total_cents = set.inject(0) { |s, i| s + (i[:owed_cents] || 0) }
                  return set if total_cents == desired_cents || (desired_cents > total_cents && (desired_cents - total_cents) <= fee_max_cents)
                end
              end
              nil
            end
        end
    end
end 
