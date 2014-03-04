module Reunion
=begin
  class EntitySearcher

    def initialize(entities)
      @e = entities
      @exact_matches = {}
      by_prefix = {}
      @by_prefix_sorted = []
      @regexes = {}

      @e.each do |name, info|
        info[:queries].each do |q|
          if q.is_a?(Regexp)
            @regexes[q] = name
          elsif q.is_a?(String) && q.length > 0
            if q[0] == "^"
              prefix = q[1..-1].downcase
              raise "Empty prefix #{q}" if prefix.nil?
              by_prefix[prefix] = name
            else
              @exact_matches[q.downcase] = name
            end
          end 
        end
      end

      #Sort longest prefixes first as they are the most specific
      #This should be replaced by a trie or something instead of a linear search
      @by_prefix_sorted = by_prefix.to_a.sort_by{|x| x[0].length}.reverse
    end 

    def search(txn_description)
      return nil if txn_description.nil? || txn_description.length == 0
      d = txn_description.downcase.strip.gsub(/\s+/," ")
      r = @exact_matches[d]
      return r unless r.nil?
      r = @by_prefix_sorted.find do |p|
        d.start_with? p[0]
      end
      return r[1] unless r.nil?
      @regexes.each do |regex, name|
        r = name if d =~ regex
        break unless r.nil?
      end
      return r
    end 

  end 

  class EntityContext

    def initialize
      @stack = []
      @entities = {}
      @searcher = nil
    end

    def [](key)
      key = key.is_a?(Symbol) ? key : key.to_s.downcase.to_sym
      @entities[key] ||= {}
      @entities[key]
    end 

    def eval(to_push, &block)
      @stack << to_push
      r = self.instance_eval(&block)
      add_hash(r) if r.is_a?(Hash)
      @stack.pop
      nil
    end

    def mention(commentary, &block)
      eval({commentary: commentary}, &block)
    end 

    def with_focus(tag, &block)
      eval({focus: tag}, &block)
    end

    def invalidate_searcher
      @searcher = nil
    end 

    def get_searcher
      @searcher ||= EntitySearcher.new(@entities)
    end

    def add_hash(pairs)
      pairs.each do |k,v|
        add_entity k,v
      end 
    end 

    def add_entity(name, value)
      invalidate_searcher
      v = self[name] 
      v[:queries] ||= []
      query = nil
      if value.is_a?(Hash)
        v[:description] ||= value[:description] || value[:desc] || value[:d]
        v[:focus] = [v[:focus]] + [value[:focus]] + [value[:f]] + @stack.map{|s| s[:focus]}
        v[:focus] = v[:focus].flatten.uniq.compact
        v[:commentary] ||= @stack.map{|s| s[:commentary]}.compact.last
        query = value[:queries] || value[:query] || value[:q]
      else
        query = value
      end

      if query.is_a?(Array)
        query.each{|q| add_entity(name,q)} 
      elsif query.is_a?(Regexp) || (query.is_a?(String) && query.length > 1)
        v[:queries] << query 
      elsif !query.nil?
        raise "Unknown query type #{query.inspect}"
      end 
    end

    def set_focus(name, value)
      self[name][:focus] = value
    end 
    def add(pairs =nil, &block)
      add_hash(pairs) unless pairs.nil?
      if block
        add_hash(block.call)
      end
      nil
    end

  end
=end 
  class Clients < Rules 
  end 
  class Vendors < Rules


    def add_default_vendors

      add_vendors do 

        with_focus :software do
          {parallels: "CBI*PARALLELS",
          sublime_text: "Sublime HQ Pty Ltd",
          codeweavers: "CODEWEAVERS INC",
          envato: "Envato Pty Ltd",
          macroplant: "FS *MACROPLANT",
          paddle: "Paddle.com",
          amazon_digital_services: "Amazon Digital Svcs", 
          jetbrains: "DRI*JETBRAINS"}
        end

        with_focus :advertising do

          add(
            {icontact: "ICONTACT CORPORATION",
            moo_printing: "MOO INC PRINTING", 
            vistaprint: "VISTAPR*VistaPrint.com"})

          with_focus :job_listings do
            {stack_overflow: "STACK OVERFLOW INTERNE",
            authentic_jobs: "AUTHENTICJOBS.COM",
            thirtyseven_signals_jobs: "37S*JOB BOARD LISTING"}
          end

          with_focus :domains do
            #domains
            {namecheap: ["NMC*NAMECHEAP.COM","NMC*NAME-CHEAP.COM SVC", "UnifiedRegistrar"],
            geotrust: "GEOTRUST *",
            iwantmyname: "IWANTMYNAME DOMAIN"}
          end 

        end 
        with_focus :software_service do
          {adobe: "ADOBE SYSTEMS, INC.",
          repository_hosting: "REPOSITORY HOSTING",
          ejunkie: "SINE INFO VENTURES PRIVATE LIMITED",
          github: ["GH *GITHUB.COM 11RI8", "HTTP//GITHUB.COM/C"],
          browserstack: "BROWSERSTACK.COM",
          zoho: "ZOHO CORPORATION",
          xero: "XERO INC",
          less_accounting: "LESSACCOUNTING",
          hellofax: "HELLOFAX / HELLOSIGN",
          sanebox: "SANEBOX",
          paypal_payflow: ["PAYFLOW/PAYPAL", "PAY FLOW PRO"],
          digital_ocean: "DIGITALOCEAN",
          appharbor: "APPHARBOR",
          aws: "Amazon Web Services",
          microsoft: "^MSFT",
          app_net: "APP.NET",
          heroku: "HEROKU",
          marketcircle: "FS *MARKETCIRCLE",
          crashplan: "CODE 42 SOFTWARE INC"}
        end



        #Communications
        with_focus :communication do
          {time_warner_cable: ["INSIGHT CABLE", "TWC*TIMEWARNERCBLE"],
          skype: "Skype Communications Sarl", 
          verizon: "^VZWRLSS",
          cricket: "^VESTA *CRICKET"}
        end



        #uniform
        with_focus :clothing do
          {olukai: "OLUKAI INC - RETAIL",
          dillards: "^DILLARD'S",
          cafepress: "CPC*CAFEPRESS.COM",
          brooks_brothers: "^BROOKS BROTHERS",
          zappos: "ZAP*ZAPPOS.COM",
          casual_male: "^CASUAL MALE",
          tommy_bahama: "^TOMMY BAHAMA"}
        end

        #hardware
        with_focus :hardware do
          {apple_store: ["APL*APPLEONLINESTOREUS", "^APPLE STORE "],
          adorama: "ADORAMA INC",
          microsoft_store: "MS *MICROSOFT STORE",
          crucial: "CRUCIAL.COM",
          mediaworld: "MEDIAWORLD",
          automatic: {q: "AUTOMATIC", d:"The hardware company, not the wordpress acquisition"},
          verizon_store: "^VERIZON WRLS "}
        end

        #travel
        with_focus :travel do
          {delta: "^DELTA",
          ryanair: "^RYANAIR",
          klm: "^KLM",
          hertz: ["^PLATEPASS HERTZ", "^HERTZ"],
          hyatt: "^HYATT",
          airbnb: "^AIRBNB",
          marriott: "^MARRIOTT",
          gaylord: "^GAYLORD",
          travelocity: "^RES TRAVELOCITY",
          aaa: "^AAA",
          kroger_fuel: "^KROGER FUEL "}
        end

        #training
        with_focus :training do
          {shiprise: {q:"SHIPRISE", d:"RubyTapas, Avdi Grimm screencasts"},
          oreilly: "O'REILLY MEDIA",
          pragmatic_programmers: "PRAGMATIC PROGRAMMERS"}
        end

        #shipping
        with_focus :shipping do
          {ups: ["^THE UPS STORE", "^UPS*"],
          usps: "^USPS"}
        end

        with_focus :insurance do
          {auto_owners_insurance: "AUTO OWNERS INSURANCE"}
        end 
        
        #office 
        with_focus :office do
          {staples: /\ASTAPLE?S?\s*[0-9]/i,
          target: "^TARGET ",
          walmart: "^WAL-MART ",
          lowes: "^LOWES ",
          samsclub: "^SAMSCLUB ",
          kroger: "^KROGER ",
          whole_foods: "^WHOLEFDS ",
          ikea: "^IKEA ",
          amazon: ["Amazon.com","AMAZON MKTPLACE PMTS"]}
        end

        #power
        with_focus :utilities do
          {duke_energy: "SPEEDPAY:DUKE-ENERGY"}
        end

        add do
          {itunes_store: "iTunes Store",
          amazon_services_kindle: "Amazon Services-Kindle",
          netflix: "Netflix, Inc.",
          longhorn_steakhouse: "LONGHORN STEAK00052811",
          turbotax: "INTUIT *TURBOTAX"}

        end

      end 

    end
  end
end




