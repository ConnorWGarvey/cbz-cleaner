require 'open3'

class Shell
  def self.run(command)
    out, status = Open3.capture2e(*command)
    if status != 0
      raise ShellError.new(out)
    end
    out
  end
end

class ShellError < StandardError
  def initialize(message)
    super(message)
  end
end

