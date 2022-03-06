#!/usr/bin/env groovy

import java.nio.file.StandardCopyOption
import java.nio.file.Files
import java.nio.file.FileSystems
import java.nio.file.LinkOption
import java.nio.file.Path
import java.nio.file.attribute.GroupPrincipal
import java.nio.file.attribute.PosixFileAttributes
import java.nio.file.attribute.PosixFileAttributeView
import java.util.zip.ZipEntry
import java.util.zip.ZipFile
import java.util.zip.ZipOutputStream

class Packager {
  static ARCHIVE_EXTENSIONS = ['cbz'].toSet()
  static GARBAGE_DIRECTORIES = ['__MACOSX/'].toSet()
  static GARBAGE_FILES = ['.DS_Store','mimetype'].toSet()
  static IMAGE_EXTENSIONS = ['jpeg','jpg','png','webp'].toSet()

  boolean allFilesAreInOneDirectory(Path path) {
    new ZipFile(path.toFile()).withCloseable { zip ->
      def entries = sortedEntries(zip.entries())
      def directoryEntries = entries.findAll{it.isDirectory()}
      if (directoryEntries.size() != 1) return false
      def directoryEntry = directoryEntries[0]
      if (entries.any{(!it.isDirectory()) && (!it.name.startsWith(directoryEntry.name))}) return false
      true
    }
  }

  boolean anyZipEntry(Path path, Closure closure) {
    new ZipFile(path.toFile()).withCloseable { zip ->
      sortedEntries(zip.entries()).any{closure.call(it)}
    }
  }

  void eachZipEntryIndexed(Path path, Closure closure) {
    everyZipEntryIndexed(path) { entry, size, index ->
      closure.call(entry, size, index)
      return true
    }
  }

  boolean everyZipEntry(Path path, Closure closure) {
    everyZipEntryIndexed(path) { entry, size, index -> closure.call(entry) }
  }

  boolean everyZipEntryIndexed(Path path, Closure closure) {
    new ZipFile(path.toFile()).withCloseable { zip ->
      def entries = sortedEntries(zip.entries())
      def size = zip.size()
      def index = 0
      entries.every{closure.call(it, size, index++)}
    }
  }

  /** File names are sequential numbers */
  boolean filesAreCorrectlyNumbered(Path path) {
    everyZipEntryIndexed(path) { entry, size, index ->
      def expectedName = String.format("%0${size.toString().length()}d", index+1)
      fileNameWithoutExtension(entry) == expectedName
    }
  }

  String fileName(ZipEntry entry) {
    def fullName = entry.name
    def name = null
    if (fullName.endsWith('/')) name = fullName[0..-2]
    else name = fullName.contains('/') ? fullName[fullName.lastIndexOf('/')+1..-1] : fullName
    if (!isKnownFileType(name)) {
      throw new IllegalStateException("Unknown file type: $name")
    }
    name
  }

  String fileNameWithoutExtension(ZipEntry entry) {
    def name = fileName(entry)
    name[0..name.lastIndexOf('.')-1]
  }

  boolean hasGarbageDirectories(Path path) {
    anyZipEntry(path) { entry ->
      entry.isDirectory() && entry.name.toString() in GARBAGE_DIRECTORIES
    }
  }

  boolean hasGarbageFiles(Path path) {
    anyZipEntry(path) { fileName(it) in GARBAGE_FILES }
  }

  boolean isKnownFileType(String name) {
    if (name in GARBAGE_FILES) return true
    def extension = name[name.lastIndexOf('.')+1..-1]
    extension in IMAGE_EXTENSIONS
  }

  Path makeTempPath(Path file, String tag) {
    def fullFileName = file.fileName.toString()
    def fileName = fullFileName[fullFileName.lastIndexOf('/')+1..fullFileName.lastIndexOf('.')-1]
    def fileExtension = fullFileName[fullFileName.lastIndexOf('.')+1..-1]
    file.parent.resolve("$fileName-${tag}.$fileExtension")
  }

  void moveFile(Path from, Path to) {
    GroupPrincipal group = Files.readAttributes(to, PosixFileAttributes.class, LinkOption.NOFOLLOW_LINKS).group();
    Files.getFileAttributeView(from, PosixFileAttributeView.class, LinkOption.NOFOLLOW_LINKS).setGroup(group);
    //Files.setOwner(fileTemp, Files.getOwner(file.parent))
    Files.move(from, to, StandardCopyOption.REPLACE_EXISTING)
  }
 
  void moveFilesOutOfDirectory(Path file) {
    assert Files.isRegularFile(file)
    def fileTemp = makeTempPath(file, 'nodirectory')
    new ZipFile(file.toFile()).withCloseable { zipIn ->
      new ZipOutputStream(Files.newOutputStream(fileTemp)).withCloseable { zipOut ->
        sortedEntries(zipIn.entries()).findAll{!it.isDirectory()}.each { entryIn ->
          def nameOut = entryIn.name[entryIn.name.lastIndexOf('/')+1..-1]
          writeEntry(entryIn:entryIn, nameOut:nameOut, zipIn:zipIn, zipOut:zipOut)
        }
        zipOut.finish()
      }
    }
    moveFile(fileTemp, file)
  }

  void removeGarbageDirectories(Path file) {
    assert Files.isRegularFile(file)
    def fileTemp = makeTempPath(file, 'withoutgarbagedirectories')
    new ZipFile(file.toFile()).withCloseable { zipIn ->
      new ZipOutputStream(Files.newOutputStream(fileTemp)).withCloseable { zipOut ->
        def entries = zipIn.entries().toList().toSorted{it.name}
        for (entryIn in entries) {
          if (!GARBAGE_DIRECTORIES.any{entryIn.name.toString().startsWith(it)}) {
            writeEntry(entryIn:entryIn, nameOut:entryIn.name, zipIn:zipIn, zipOut:zipOut)
          }
        }
        zipOut.finish()
      }
    }
    moveFile(fileTemp, file)
  }

  void removeGarbageFiles(Path file) {
    assert Files.isRegularFile(file)
    def fileTemp = makeTempPath(file, 'withoutgarbagefiles')
    new ZipFile(file.toFile()).withCloseable { zipIn ->
      new ZipOutputStream(Files.newOutputStream(fileTemp)).withCloseable { zipOut ->
        def entries = zipIn.entries().toList()
        for (entryIn in entries) {
          if (!(entryIn.name.toString() in GARBAGE_FILES)) {
            writeEntry(entryIn:entryIn, nameOut:entryIn.name, zipIn:zipIn, zipOut:zipOut)
          }
        }
        zipOut.finish()
      }
    }
    moveFile(fileTemp, file)
  }

  void renumberFiles(Path file) {
    assert Files.isRegularFile(file)
    def fileTemp = makeTempPath(file, 'renumbered')
    new ZipFile(file.toFile()).withCloseable { zipIn ->
      new ZipOutputStream(Files.newOutputStream(fileTemp)).withCloseable { zipOut ->
        sortedEntries(zipIn.entries()).eachWithIndex { entryIn, index ->
          def oldName = entryIn.name
          def extension = oldName[oldName.lastIndexOf('.')+1..-1]
          def number = String.format("%0${zipIn.size().toString().length()}d", index+1)
          writeEntry(entryIn:entryIn, nameOut:"${number}.$extension", zipIn:zipIn, zipOut:zipOut)
        }
        zipOut.finish()
      }
    }
    moveFile(fileTemp, file)
  }

  void repackageAll(Path directory) {
    assert Files.isDirectory(directory)
    directory.eachFile { file ->
      def fileName = file.fileName.toString()
      def extension = fileName[fileName.lastIndexOf('.')+1..-1]
      if (!(extension in ARCHIVE_EXTENSIONS)) {
        return
      }
      println fileName
      if (Files.isDirectory(file)) return
      if (hasGarbageDirectories(file)) {
        println '  Cleaning garbage directories'
        removeGarbageDirectories(file)
      }
      if (allFilesAreInOneDirectory(file)) {
        println '  Moving files out of directory'
        moveFilesOutOfDirectory(file)
      }
      if (hasGarbageFiles(file)) {
        println '  Cleaning garbage files'
        removeGarbageFiles(file)
      }
      if (!filesAreCorrectlyNumbered(file)) {
        println '  Renumbering'
        renumberFiles(file)
      }
    }
  }

  List<? extends ZipEntry> sortedEntries(Enumeration<? extends ZipEntry> enumeration) {
    def entries = enumeration.toList()
    // Every file ends with a dash or underscore, then a number
    if (entries.every{!it.isDirectory()} && entries.every{fileNameWithoutExtension(it) ==~ /.*[_\-\#]\d+/}) {
      entries.
        // Group by prefix
        groupBy{(fileNameWithoutExtension(it) =~ /(.*)[_\-\#]\d+$/)[0][1]}.
        // Sort each group by postfix
        collectEntries { prefix, groupedEntries ->
          [prefix, groupedEntries.toSorted { entry ->
            def name = fileNameWithoutExtension(entry)
            def number = (name =~ /\d+$/)[0]
            number.toBigInteger()
          }]
        }.
        // Sort by prefix
        toSorted{e1, e2 -> e1.key <=> e2.key}.
        collect{it.value}.
        flatten()
    } else if (entries.every{!it.isDirectory()} && entries.every{fileNameWithoutExtension(it).isInteger()}) {
      entries.toSorted {fileNameWithoutExtension(it).toBigInteger()}
    } else {
      entries.toUnique{it.name}.toSorted{it.name}
    }
  }

  void writeEntry(Map opts) {
    def zipOut = opts.zipOut
    def entryOut = new ZipEntry(opts.nameOut)
    zipOut.putNextEntry(entryOut)
    opts.zipIn.getInputStream(opts.entryIn).withCloseable { content ->
      content.transferTo(zipOut)
    }
    zipOut.closeEntry()
  }
}

new Packager().repackageAll(FileSystems.getDefault().getPath('.'))

