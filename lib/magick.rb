require_relative 'shell'

class Magick
  def self.convert(operations:[:trim, :resize], quality:, source:, target:)
    command = make_convert_command(operations:operations, quality:quality, source:source, target:target)
    Shell.run(command)
  end

  private

  def self.make_convert_command(operations:, quality:, source:, target:)
    compression_options = if target.extension == 'webp'
      if quality == :lossless
        ['-define', 'webp:lossless=true']
      else
        ['-quality', "#{quality}%"]
      end
    else
      []
    end
    operation_options = operations.reduce([]) do |acc, symbol|
      case symbol
        when :deskew
          acc.concat(['deskew', '40%', '+repage'])
        when :resize
          acc.concat(['-resize', '2700>x2700>', '+repage'])
        when :trim
          acc.concat(['-fuzz', '7%', '-trim', '+repage'])
        else
          raise "Unknown operation #{operation}"
      end
    end
    ['convert', '-alpha', 'flatten', source.absolute.to_s] + operation_options + compression_options + [target.to_s]
  end
end

