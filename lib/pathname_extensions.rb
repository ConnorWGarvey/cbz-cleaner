require 'fileutils'
require 'pathname'
require 'zip'

module PathnameFunctions
  def absolute = self.realpath
  def basename_without_extension = basename('.*')

  def basename_without_trailing_slash
    text = basename.to_s
    text.end_with?('/') ? text[0..-2] : text
  end

  def child(name) = self + name

  def children_with_extension(extension, exclude:[])
    children.select{|f|(f.extension == extension) && !exclude.map{|e|e.absolute.to_s}.include?(f.absolute.to_s)}
  end

  # Copies the contents of a directory to a zip file. Currently not recursive, doesn't copy subdirectories.
  # @param target the target zip file
  # @param naming (optional) :source is default
  #   :incrementing : integers zero padded to the longest number length with the original file name
  #   :source : source file names
  def copy_directory_to_zip(target, naming: :source)
    puts("  Compressing the #{target.extension.upcase}")
    namer = if naming == :incrementing
      digits = children.size.to_s.length
      Proc.new{|n,i|"%0#{digits}d" % i}
    elsif naming == :source
      Proc.new{|n|n}
    else
      raise StandardError.new("Unknown naming: #{naming}")
    end
    Zip::File.open(target, create:true) do |zip|
      each_file_sorted do |source_path, index|
        target_name = "#{namer.call(source_path.basename_without_extension, index)}#{source_path.extname}"
        zip.get_output_stream(target_name) do |writer|
          source_path.open do |reader|
            while block = reader.read(1024**2)
              writer << block
            end
          end
        end
      end
    end
  end

  def copy_permissions_to(to)
    user = nil # must be root to set user
    group = stat.gid # group number
    mode = stat.mode # integer
    if directory?
      # Remove executable bits
      mode = mode.to_s.split('').map{|i|i.to_i}.map{|i|i.odd? ? i-1 : i}.join.to_i
    end
    to.chmod(mode)
    to.chown(user, group)
  end

  def create_sibling_directory(name) = sibling(name).make_directory
  def create_sibling_directory_with_appendix(appendix) = create_sibling_directory(basename_without_trailing_slash + appendix)

  def delete_directory
    FileUtils.rm_r(self) if exist?
  end

  def directory_is_empty? = children.empty?

  def each_directory
    each_child do |f|
      yield f if f.directory?
    end
  end

  def each_file
    i = -1
    each_child do |f|
      i += 1
      yield(f, i) if f.file?
    end
  end

  def each_file_sorted
    children.sort.each_with_index do |f, i|
      yield(f, i) if f.file?
    end
  end

  def extension = extname[1..-1]

  def make_directory()
    Dir.mkdir(self)
    self
  end

  def make_directories = FileUtils.mkdir_p(self)

  def move(target) = FileUtils.mv(self, target)

  def move_with_permissions(target)
    target.copy_permissions_to(self)
    move(target)
    target
  end

  def parent = self.dirname
  def sibling(name) = parent.child(name)
  def sibling_with_appendix(appendix) =
    if file?
      sibling("#{basename_without_extension}#{appendix}#{extname}")
    elsif directory?
      sibling(basename + appendix)
    end
  def with_extension(ext) = parent.child("#{basename_without_extension}.#{ext}")
end
Pathname.class_eval{include PathnameFunctions}

