require 'pp'
class Reunion::BankAccount
  def merge_duplicate_transactions(all_transactions)

    match = lambda { |t|  t.date_str + "|" + ("%.2f" %  t.amount) + "|" + t.description.strip.squeeze(" ").downcase  }

    #We have to give each transaction a unique index so we can do set math without accidentially removing similar txns
    #And so we can resort correctly at the end
    all_transactions.each_with_index { |v, i| v[:temp_index] = i}
    
    all_transactions = all_transactions.stable_sort_by { |t| match.call(t)}

    #Group into matching transactions
    matches = all_transactions.chunk(&match).map{|t| t[1]}
    matches = matches.map do |group|
      
      log_it = false #group.any? {|r| r[:description] =~ /DELTA AIR LINE/i}
      if log_it
        p 
        pp group 
        p
      end 

      next group unless group.count > 1


      uniq_ids = group.uniq{|t| t.id}.reject { |t| t.id.nil? }
      remainder = group - uniq_ids

      subgroups = []
      #Start with with IDs. Merge matching ID transactions, followed by 1 non-id  transaction from every unrepresented source 
      subgroups += uniq_ids.map do |with_id|
        # Collect transactions with matching IDs
        take = [with_id] + remainder.select {|r| r.id == with_id.id}
        remainder -= take
        take = (take + remainder).uniq{|k| k.source}
        remainder -= take
        take 
      end 
      #Group remaining transactions into subgroups (each subgroup only has 1 txn per source)
      until remainder.empty? do
        take = remainder.uniq{|t| t.source}
        subgroups << take
        remainder -= take;
      end

      

      p "Merging #{group.count} transactions into #{subgroups.count}" if log_it

      result = []
      result = subgroups.map do |subgroup| 
        subgroup = subgroup.sort_by{|t| t[:priority]}

        if log_it
          pp "--- this sub group ---"
          pp subgroup

          pp "--- Becomes ---"
        end 

        has_primary_txn = subgroup.any?{|t| t[:discard_if_unmerged].nil? }

        if has_primary_txn
          subgroup.each{|t| t.delete(:discard_if_unmerged)}
          subgroup.inject(Reunion::Transaction.new(schema: schema)){|acc, current| acc.merge_transaction(current)}
        else 
          subgroup
        end 
      end 



      result
    end 

    matches = matches.flatten.map do |t|
      if t[:discard_if_unmerged]
        t[:discard] = true
        t[:discard_reason] = "Shadow transaction remains unmerged"
        t.delete(:discard_if_unmerged)
        nil
      else
        t
      end
    end.compact

    #Restore order
    matches.sort_by! {|x| [x.date_str, x[:temp_index]]}
    matches.each{|x| x.delete(:temp_index)}
    
    matches
  end 
end
