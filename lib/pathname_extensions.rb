require 'bigdecimal'
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

  def child_directories(exclude:[])
    children.select{|c|c.directory? && !exclude.map{|e|e.absolute.to_s}.include?(c.absolute.to_s)}
  end

  def child_files(exclude:[], select_extensions:nil)
    children.select{|c|c.file? && !exclude.map{|e|e.absolute.to_s}.include?(c.absolute.to_s) && (select_extensions.nil? || select_extensions.include?(c.extension))}
  end

  def children? = !children.empty?

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
      Proc.new{|n,i|"%0#{digits}d" % (i+1)}
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
    if directory? && to.file?
      # Remove executable bits by masking 0111 (if a number has 1 added to it, it's executable)
      # Mode numbers are octal. In Ruby, to make a number octal, prefix it by "0"
      mode = mode ^ (mode & 0111)
    end
    to.chmod(mode)
    to.chown(user, group)
  end

  def create_sibling_directory(name) = sibling(name).make_directory

  def create_sibling_directory_with_appendix(appendix)
    if file?
      create_sibling_directory(dirname + "#{basename_without_extension.to_s}#{appendix}")
    else
      create_sibling_directory(basename_without_trailing_slash + appendix)
    end
  end

  def delete_directory
    FileUtils.rm_r(self) if exist?
  end

  def directory_is_empty? = children.empty?

  def each_directory
    each_child do |f|
      yield f if f.directory?
    end
  end

  def each_file(exclude:[], exclude_extensions:[])
    i = -1
    each_child do |f|
      i += 1
      yield(f, i) if f.file? && !exclude.include?(f.basename.to_s) && !exclude_extensions.include?(f.extension)
    end
  end

  def each_file_sorted
    children.sort.each_with_index do |f, i|
      yield(f, i) if f.file?
    end
  end

  def extension = extname[1..-1]

  def first_child
    children.size > 0 ? children[0] : nil
  end

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
  def sibling_with_appendix(suffix) =
    if directory?
      sibling(basename_without_trailing_slash + suffix)
    elsif extname.empty?
      sibling(basename + suffix)
    else
      sibling("#{basename_without_extension}#{suffix}#{extname}")
    end
  def with_extension(ext) = parent.child("#{basename_without_extension}.#{ext}")

  def sorted_children
    # Every child that is a file ends with a dash or underscore, then a number
    if child_files.all?{|e|e.basename_without_extension.to_s.match?(/[_\-\#] ?\d+(?:\.\d+)?\Z/)}
      child_directories.sort +
      child_files.
        # Group by prefix
      group_by{|e|e.basename_without_extension.to_s.match(/(.*)[_\-\#] ?\d+(?:\.\d+)?\Z/)[1]}.
        # Sort each group by postfix
      map{|prefix, grouped_entries|[prefix, grouped_entries.sort_by{|e|BigDecimal(e.basename_without_extension.to_s.match(/\d+(?:\.\d+)?\Z/)[0])}]}.to_h.
        # Sort groups by prefix
        sort.to_h.
        values.
        flatten
    # Every child is a file with a name that's an integer
    elsif children.all?{|c|!c.directory? && c.basename_without_extension.to_s.integer?}
      children.sort_by{|c|basename_without_extension.to_i}
    else
      children.uniq{|c|c.to_s}.sort_by{|c|c.to_s}
    end
  end

  def sorted_children_with_extension(extension, exclude:[])
    sorted_children.select{|c|c.file?}.select{|f|(f.extension == extension) && !exclude.map{|e|e.absolute.to_s}.include?(f.absolute.to_s)}
  end
end
Pathname.class_eval{include PathnameFunctions}

