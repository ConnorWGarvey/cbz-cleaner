require_relative 'pathname_extensions'
require_relative 'string_extensions'
require 'pathname'
require 'set'
require 'tempfile'
require 'zip'

GARBAGE_DIRECTORIES = Set['__MACOSX']
GARBAGE_FILES = Set['.DS_Store','mimetype']
IMAGE_EXTENSIONS = Set['jpeg','jpg','png','webp']

Zip::Entry.class_eval do
  def any_ancestor?(&block) = any_ancestor_name?(name, &block)

  def basename
    chopped = name.end_with?('/') ? name[0..-2] : name
    chopped.substring_after_last('/').to_s
  end

  def basename_without_extension = basename.substring_before_last('.')

  # Copies the entry to a file identified by a Pathname
  def copy_to_pathname(pathname)
    if name_is_directory?
      FileUtils.mkdir_p(pathname)
    else
      FileUtils.mkdir_p(pathname.dirname)
      File.open(pathname, "wb"){|file|write_to(file)}
    end
  end
  
  def copy_to_directory(directory)
    copy_to_pathname(directory.join(basename))
  end

  def copy_to_zip(zip, name:) = name_is_directory? ? zip.mkdir(name) : zip.get_output_stream(name){|writer|write_to(writer)}
  # Determines whether the entry is or is in a garbage directory
  def in_garbage_directory? = any_ancestor?{|a|GARBAGE_DIRECTORIES.include?(a.substring_after_last('/'))}

  def write_to(writer)
    get_input_stream do |reader|
      while block = reader.read(1024**2)
        writer << block
      end
    end
  end

  def extension = basename.substring_after_last('.')
  def known_type? = GARBAGE_FILES.include?(name) || IMAGE_EXTENSIONS.include?(extension)
  def name_is_file? = !name_is_directory?
  def to_path = Pathname.new(name)

  private

  def any_ancestor_name?(path, &block)
    chopped = path.end_with?('/') ? path[0..-2] : path
    parent = parent(chopped)
    block.call(chopped) || (parent && any_ancestor_name?(parent, &block))
  end

  def parent(path)
    chopped = path.end_with?('/') ? path[0..-2] : path
    path.include?('/') ? path[0..path.rindex('/')-1] : nil
  end
end

# Add class methods
Zip::File.instance_eval do
  def all_files_in_one_directory?(path)
    open(path) do |zip|
      entries = zip.entries
      directory_entries = entries.select{|e|e.name_is_directory?}
      if directory_entries.size != 1
        false
      else
        directory_entry = directory_entries[0]
        entries.all?{|e|!e.name_is_directory? || e.name.start_with?(directory_entry.name)}
      end
    end
  end

  # File names are sequential numbers
  def files_numbered?(path)
    with_entries(path) do |entries|
      digits = entries.size.to_s.length
      name_format = "%0#{digits}d"
      entries.to_enum.with_index.all? do |entry, index|
        expected_name = name_format % (index+1)
        entry.basename_without_extension == expected_name
      end
    end
  end

  def garbage_directories?(path) = with_entries(path){|es|es.any?{|e|e.name_is_directory? && GARBAGE_DIRECTORIES.include?(e.basename)}}
  def garbage_files?(path) = with_entries(path){|es|es.any?{|e|GARBAGE_FILES.include?(e.basename)}}

  # Assuming all files are in one directory, moves files out of that directory
  def move_files_out_of_directory(file)
    atomically_modify(file, tag:'-nodirectory') do |source_zip, target_zip|
      source_zip.sorted_files.each{|entry|entry.copy_to_zip(target_zip, name:entry.basename)}
    end
  end

  def remove_garbage_directories(file)
    atomically_modify(file, tag:'-withoutgarbagedirectories') do |source_zip, target_zip|
      source_zip.sorted_entries.each do |entry|
        entry.copy_to_zip(target_zip, name:entry.name) unless entry.in_garbage_directory?
      end
    end
  end

  def remove_garbage_files(file)
    atomically_modify(file, tag:'-withoutgarbagefiles') do |source_zip, target_zip|
      source_zip.entries.each do |entry|
        entry.copy_to_zip(target_zip, name:entry.name) unless GARBAGE_FILES.include?(entry.basename)
      end
    end
  end

  def renumber_files(file)
    atomically_modify(file, tag:'-renumbered') do |source_zip, target_zip|
      digits = source_zip.entries.size.to_s.length
      name_format = "%0#{digits}d"
      source_zip.entries.to_enum.with_index.each do |entry, index|
        entry.copy_to_zip(target_zip, name:"#{name_format % (index+1)}.#{entry.extension}")
      end
    end
  end

  def with_entries(path) = open(path){|zip|yield zip.entries}

  def with_sorted_entries(path, exclude_extensions: []) = open(path){|zip|zip.sorted_entries(exclude_extensions: exclude_extensions).each{|e|yield e}}

  private

  # Opens a temp file for writing and an existing zip for reading, yields both, then replaces the source zip with the written temp file.
  # @yields Zip::File,Zip::File (open target zip, open source zip)
  def atomically_modify(source, tag:)
    file_temp = source.sibling_with_appendix(tag)
    begin
      open(file_temp, create:true) do |temp_zip|
        open(source){|source_zip|yield(source_zip, temp_zip)}
      end
      Pathname.new(file_temp).move_with_permissions(source)
    rescue
      begin
        file_temp.delete
      rescue
        #ignore
      end
      raise
    end
  end
end

Zip::File.class_eval do
  def sorted_entries(exclude_extensions: [])
    # Every file ends with a dash or underscore, then a number
    if entries.all?{|e|!e.name_is_directory? && e.basename_without_extension.match?(/[_\-\#]\d+\Z/)}
      entries.
        # Group by prefix
        group_by{|e|e.basename_without_extension.match(/(.*)[_\-\#]\d+\Z/)[1]}.
        # Sort each group by postfix
        map{|prefix, grouped_entries|[prefix, grouped_entries.sort_by{|e|e.basename_without_extension.match(/\d+\Z/)[0].to_i}]}.to_h.
        # Sort groups by prefix
        sort.to_h.
        values.
        flatten
    elsif entries.all?{|e|!e.name_is_directory? && e.basename_without_extension.integer?}
      entries.sort_by{|e|basename_without_extension.to_i}
    else
      entries.uniq{|e|e.name}.sort_by{|e|e.name}
    end.select{|e|!exclude_extensions.include?(e.extension)}
  end

  def sorted_files
    sorted_entries.select{|e|e.name_is_file?}
  end
end

