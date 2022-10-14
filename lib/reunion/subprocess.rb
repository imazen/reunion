module Reunion
    module Subprocess
        


        require 'open3'

cmd = './packer_mock.sh'
data = {:out => [], :err => []}

# see: http://stackoverflow.com/a/1162850/83386
Open3.popen3(cmd) do |stdin, stdout, stderr, thread|
  # read each stream from a new thread
  { :out => stdout, :err => stderr }.each do |key, stream|
    Thread.new do
      until (raw_line = stream.gets).nil? do
        parsed_line = Hash[:timestamp => Time.now, :line => "#{raw_line}"]
        # append new lines
        data[key].push parsed_line
        
        puts "#{key}: #{parsed_line}"
      end
    end
  end

  thread.join # don't exit until the external process is done
end
    end
end 