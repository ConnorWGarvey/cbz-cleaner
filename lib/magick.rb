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

  def self.trim_all(compression:, directory:, trim_count:, suffix:)
    source_directory = directory
    action_name = trim_count > 0 ? 'Trimming' : 'Resizing'
    puts("  #{action_name} images in #{directory.basename}")
    read_from_directory = directory
    trim_directories = []
    begin
      for i in 2..trim_count
        puts("    Extra trim #{i}")
        iteration = i-1
        trim_directory = directory.create_sibling_directory_with_appendix("-trim-#{i}")
        read_from_directory.each_file(exclude:['.nomedia']) do |source_path|
          trim_path = trim_directory.child(source_path.with_extension('webp').basename)
          puts("      Trimming #{source_path.basename} -> #{trim_path.extension}")
          Magick.convert(quality: :lossless, source:source_path, target:trim_path)
        end
        trim_directories << trim_directory
        read_from_directory = trim_directory
      end
      target_directory = source_directory.create_sibling_directory_with_appendix(suffix)
      puts("    #{action_name}")
      read_from_directory.each_file(exclude:['.nomedia']) do |source_path|
        target_path = target_directory.child("#{source_path.basename_without_extension}.#{compression}")
        if !target_path.exist?
          puts("      #{action_name} #{source_path.basename} -> #{target_path.extension}")
          operations = (trim_count>0) ? [:trim, :resize] : [:resize]
          Magick.convert(operations:operations, quality:94, source:source_path, target:target_path)
        end
      end
    ensure
      trim_directories.each do |d|
        begin
          d.delete_directory
        rescue
        end
      end
    end
    target_directory
  end
end

