module Reunion
  class Clients < Rules 
  end 
  class Vendors < Rules

    def add_default_vendors

      add_vendors do 

        use_vendor_tag :software do
          {parallels: "CBI*PARALLELS",
          sublime_text: "Sublime HQ Pty Ltd",
          codeweavers: "CODEWEAVERS INC",
          envato: "Envato Pty Ltd",
          macroplant: "FS *MACROPLANT",
          paddle: "Paddle.com",
          amazon_digital_services: "Amazon Digital Svcs", 
          jetbrains: "DRI*JETBRAINS"}
        end

        use_vendor_tag :advertising do

          add(
            {icontact: "ICONTACT CORPORATION",
            moo_printing: "MOO INC PRINTING", 
            vistaprint: "VISTAPR*VistaPrint.com"})

          use_vendor_tag :job_listings do
            {stack_overflow: "STACK OVERFLOW INTERNE",
            authentic_jobs: "AUTHENTICJOBS.COM",
            thirtyseven_signals_jobs: "37S*JOB BOARD LISTING"}
          end

          use_vendor_tag :domains do
            #domains
            {namecheap: ["NMC*NAMECHEAP.COM","NMC*NAME-CHEAP.COM SVC", "UnifiedRegistrar"],
            geotrust: "GEOTRUST *",
            iwantmyname: "IWANTMYNAME DOMAIN"}
          end 

        end 
        use_vendor_tag :software_service do
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
        use_vendor_tag :communication do
          {time_warner_cable: ["INSIGHT CABLE", "TWC*TIMEWARNERCBLE"],
          skype: "Skype Communications Sarl", 
          verizon: "^VZWRLSS",
          cricket: "^VESTA *CRICKET"}
        end



        #uniform
        use_vendor_tag :clothing do
          {olukai: "OLUKAI INC - RETAIL",
          dillards: "^DILLARD'S",
          cafepress: "CPC*CAFEPRESS.COM",
          brooks_brothers: "^BROOKS BROTHERS",
          zappos: "ZAP*ZAPPOS.COM",
          casual_male: "^CASUAL MALE",
          tommy_bahama: "^TOMMY BAHAMA"}
        end

        #hardware
        use_vendor_tag :hardware do
          {apple_store: ["APL*APPLEONLINESTOREUS", "^APPLE STORE "],
          adorama: "ADORAMA INC",
          microsoft_store: "MS *MICROSOFT STORE",
          crucial: "CRUCIAL.COM",
          mediaworld: "MEDIAWORLD",
          automatic: {q: "AUTOMATIC", d:"The hardware company, not the wordpress acquisition"},
          verizon_store: "^VERIZON WRLS "}
        end

        #travel
        use_vendor_tag :travel do
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
        use_vendor_tag :training do
          {shiprise: {q:"SHIPRISE", d:"RubyTapas, Avdi Grimm screencasts"},
          oreilly: "O'REILLY MEDIA",
          pragmatic_programmers: "PRAGMATIC PROGRAMMERS"}
        end

        #shipping
        use_vendor_tag :shipping do
          {ups: ["^THE UPS STORE", "^UPS*"],
          usps: "^USPS"}
        end

        use_vendor_tag :insurance do
          {auto_owners_insurance: "AUTO OWNERS INSURANCE"}
        end 
        
        #office 
        use_vendor_tag :office do
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
        use_vendor_tag :utilities do
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




