#This class expects input files will be named "Account-filetag-filenameorwhatever.{csv,tsv,txt,qbo,qfx}"
module Reunion
  class StandardFileLocator

    def initialize
      @input_dirs = []
      @input_pathspec = "**/*.{csv,tsv,txt,qbo,qfx}"
    end

    attr_accessor :input_dirs, :input_pathspec, :working_dir

 
    def generate_input_filenames 
      input_dirs.map do |input_dir| 
        Dir.glob(File.join(File.expand_path(input_dir, working_dir), input_pathspec),File::FNM_CASEFOLD)
      end.flatten.select { |p| File.basename(p).split('-').length > 2 && (p =~ /\.normal\.txt\Z/i).nil? }
    end

    def generate_file_objects
      generate_input_filenames.map do |path|
        f = InputFile.new
        f.full_path = path
        f.path = File.expand_path(path).gsub(File.expand_path(working_dir), "").gsub(/\A\/+/,"")
        f.account_tag = File.basename(path).split('-')[0].downcase.to_sym
        f.parser_tag = File.basename(path).split('-')[1].downcase.to_sym 
        f
      end
    end

    def generate_and_assign(parser_table, accounts_table)
      generate_file_objects.map do |f|
        f.parser = parser_table[f.parser_tag]
        matching_accounts = [accounts_table[f.account_tag]].flatten
        copies = matching_accounts.map do |a|
          copy = f.clone
          copy.account = a
          a.input_files << copy unless copy.parser.nil? || a.nil?
          copy
        end
        copies ||= [f] #Don't forget input files without matching accounts
        copies
      end.flatten
    end
  end 
end

