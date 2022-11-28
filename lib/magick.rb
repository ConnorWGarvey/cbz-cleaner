require_relative 'shell'

class Magick
  def self.convert(quality:, source:, target:)
    command = make_convert_command(quality:quality, source:source, target:target)
    Shell.run(command)
  end

  private

  def self.make_convert_command(quality:, source:, target:)
    compression_options = if target.extension == 'webp'
      if quality == :lossless
        ['-define', 'webp:lossless=true']
      else
        ['-quality', "#{quality}%"]
      end
    else
      []
    end
    ['convert', '-alpha', 'flatten', source.absolute.to_s, '-fuzz', '7%', '-trim', '+repage', '-resize', '2700>x2700>', '+repage'] + compression_options + [target.to_s]
  end
end

