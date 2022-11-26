require 'pathname'
require 'zip'

module PathnameFunctions
  def absolute() = self.realpath
  def basename_without_extension() = self.basename('.*')
  def child(name) = self + name

  def copy_permissions_to(to)
    user = nil # must be root to set user
    group = self.stat.gid # group number
    to.chown(user, group)
  end

  def delete_directory() = FileUtils.rm_r(self)

  def each_directory
    each_child do |f|
      yield f if f.directory?
    end
  end

  def each_file
    each_child do |f|
      yield f if f.file?
    end
  end

  def make_directory()
    Dir.mkdir(self)
    self
  end
  def make_directories() = FileUtils.mkdir_p(self)
  def parent = self.dirname

  def copy_directory_to_zip(target)
    puts('  Compressing the CBZ')
    Zip::File.open(target, create:true) do |zip|
      self.each_file do |source_path|
        zip.get_output_stream(source_path.basename) do |writer|
          source_path.open do |reader|
            while block = reader.read(1024**2)
              writer << block
            end
          end
        end
      end
    end
  end
end
Pathname.class_eval{include PathnameFunctions}

