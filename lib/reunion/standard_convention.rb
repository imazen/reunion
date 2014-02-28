#This class expects input files will be named "Account-filetag-filenameorwhatever.*"
module Reunion
  class StandardConvention

    def initialize
      @input_dirs = []
      @input_pathspec = "**/*.{csv,tsv,txt,qbo,qfx}"
      @accounts = []
      @parsers_by_file_tag = {}
    end

    attr_accessor :input_dirs, :input_pathspec, :working_dir, :output_reports_dir, :output_accounts_dir, :accounts, :all_input_files, :all_transactions

    def full_output_accounts_dir
      File.expand_path(output_accounts_dir, working_dir)
    end
    def full_output_reports_dir
      File.expand_path(output_reports_dir, working_dir)
    end

    def list_possible_input_filenames 
      input_dirs.map do |input_dir| 
          Dir.glob(File.join(File.expand_path(input_dir, working_dir), input_pathspec),File::FNM_CASEFOLD)
        end.flatten.select { |p| File.basename(p).split('-').length > 2 && (p =~ /\.normal\.txt\Z/i).nil? }
      end

      def populate_input_files
        fnames = list_possible_input_filenames

        @all_input_files = fnames.map do |path|
          f = InputFile.new
          f.full_path = path
          f.path = File.expand_path(path).gsub(File.expand_path(working_dir), "").gsub(/\A\/+/,"")
          f.account_tag = File.basename(path).split('-')[0]
          f.file_tag = File.basename(path).split('-')[1]
          f.parser = parsers_by_file_tag[f.file_tag.downcase.to_sym]

          matching_accounts = accounts.select{|a| a.tags.include?(f.account_tag.downcase.to_sym) }
          copies = matching_accounts.map do |a|
            copy = f.clone
            copy.account = a
            a.input_files << copy unless copy.parser.nil?
            copy
          end
          copies ||= [f] #Don't forget input files without matching accounts
          copies
        end.flatten

      end

      attr_accessor :parsers_by_file_tag

      def register_parser(file_tag, parser_class)
        parsers_by_file_tag[file_tag] = parser_class
      end


  end 
end

