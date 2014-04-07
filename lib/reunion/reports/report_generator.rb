module Reunion
  
  class ReportResult
    attr_accessor :title, :schema, :name, :path, :breadcrumbs, :nav_label, :navs, :transactions, :calculations_by_currency, :subreports
  end


  class ReportGenerator

    def generate(slugs, reports, datasource)
      slugs = slugs.map{|s| s.to_s.downcase.to_sym}
      result = ReportResult.new
      result.breadcrumbs = []

      child_reports = reports
      child_data = datasource.dup
      report = nil

      slugs.each_with_index do |name, ix|
        report = child_reports.find{|r| r.slug == name}
        result.name = name
        path = slugs[0..ix]
        result.path = path.join('/')
        raise "Failed to find report (#{path.join('/')}) during generation of (#{slugs.join('/')}) within set [#{child_reports.map{|r|r.slug}.join(',')}]\n" if report.nil?
        child_data = child_data.unfilter unless report.inherit_filters
        child_data = child_data.filter(&(report.filter)) if report.filter
        result.breadcrumbs << {name: name, path: path.join('/')}
        child_reports = report.get_child_reports(child_data)
      end

      #STDERR << "Filtered to #{child_data.results.count}"
      result.calculations_by_currency = report.get_calculations_by_currency(child_data)
      result.transactions = child_data.results
      result.title = report.title
      result.schema = datasource.schema
      result.subreports = child_reports.map{|r|
        generate(slugs + [r.slug], reports, child_data)
      }
      result
    end


  end

end