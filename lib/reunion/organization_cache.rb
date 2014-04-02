module Reunion

  class OrganizationCache
    attr_accessor :org_creator
    def initialize(&org_creator)
      @org_creator = org_creator
    end

    def org_computed
      @org_computed ||= org_parsed(deep_copy:true).ensure_computed! 
    end

    def org_parsed(deep_copy: true)
      load_parsed! unless @org_parsed_dump
      unless @org_parsed_dump
        parsed = org_creator.call()
        parsed.ensure_parsed!
        @org_parsed_dump = Marshal.dump(parsed)
        @org_parsed = parsed
        File.open(parsed_cache_path, 'w'){|f| f.write(@org_parsed_dump)}
      end 
      deep_copy ? Marshal.restore(@org_parsed_dump) : @org_parsed
    end  

    #for troubleshooting
    def find_proc(obj, chain = "", maxdepth=100)
      return if maxdepth < 0
      return unless obj
      chain = chain + "(#{obj.class})"
      puts "\n\nFound proc at #{chain}\n\n" if obj.is_a?(Proc)
      obj.instance_variables.each do |name|
        find_proc(obj.instance_variable_get(name), "#{chain}>#{name}", maxdepth-1)
      end
      if obj.is_a? Array
        obj.each_with_index do |v, ix|
          find_proc(v, "#{chain}>[#{ix}]", maxdepth-1)
        end
      end
      if obj.is_a? Hash
        obj.each do |k, v|
          find_proc(k, "#{chain}>[#{k.inspect}]",maxdepth-1)
          find_proc(v, "#{chain}>[#{k.inspect}]",maxdepth-1)
        end
      end
    end

    def invalidate_parsing!
      invalidate_computations!
      @org_parsed = nil
      @org_parsed_dump = nil
      File.delete(parsed_cache_path) if File.exist?(parsed_cache_path)
    end 
    
    def invalidate_computations!
      @org_computed = nil
    end

    def load_parsed!
      @org_parsed_dump = File.read(parsed_cache_path) if File.exist?(parsed_cache_path)
      if @org_parsed_dump
        #begin
          @org_parsed = Marshal.restore(@org_parsed_dump) 
          @org_parsed.log << "Loaded from disk (parsed_data) at #{DateTime.now}"
        #rescue => e
        #  puts "Failed to restore dump from disk"
        #  puts e
        #  @org_parsed_dump = nil
        #end
      end
    end  

    def cache_folder
      unless @cache_folder
        temp = org_creator.call()
        temp.configure
        @cache_folder = temp.root_dir
      end 
      @cache_folder
    end 

    def parsed_cache_path
      File.join(cache_folder, "parsed_data.bin")
    end

 
  end 
end