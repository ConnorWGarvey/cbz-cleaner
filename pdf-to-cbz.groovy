#!/usr/bin/env groovy

import groovy.cli.commons.CliBuilder
import java.nio.file.Files
import java.nio.file.LinkOption
import java.nio.file.Path
import java.nio.file.Paths
import java.nio.file.attribute.GroupPrincipal
import java.nio.file.attribute.PosixFileAttributes
import java.nio.file.attribute.PosixFileAttributeView
import java.util.zip.ZipEntry
import java.util.zip.ZipFile
import java.util.zip.ZipOutputStream

class Converter {
  void apply(Map opts=[:], Path file) {
    def extracted = extractImages(file)
    def name = fileNameWithoutExtension(file)
    def trimmed = trimAll(extracted, compression:opts.compression, trimCount:opts.trimCount)
    def cbz = Paths.get("${name}.cbz").toAbsolutePath()
    writeCbz(cbz, trimmed)
    copyPermissions(file, cbz)
    extracted.deleteDir()
    trimmed.deleteDir()
    if (opts.delete) Files.delete(file)
  }

  void applyAll(Map opts=[:], Path directory) {
    def done = [] as Set
    do {
      def file = firstWithExtension(directory, 'pdf', exclude:done)?.toAbsolutePath()
      if (file) {
        if (file.withExtension('cbz').exists()) println "Skipping existing ${file.fileName}"
        else {
          println "Converting ${file.fileName}"
          apply(file, compression:opts.compression, delete:opts.delete, trimCount:opts.trimCount)
        }
      }
      if (file) done << file.toAbsolutePath()
    } while (firstWithExtension(directory, 'pdf', exclude:done))
  }

  void copyPermissions(Path from, Path to) {
    GroupPrincipal group = Files.readAttributes(from, PosixFileAttributes.class, LinkOption.NOFOLLOW_LINKS).group()
    Files.getFileAttributeView(to, PosixFileAttributeView.class, LinkOption.NOFOLLOW_LINKS).setGroup(group)
    to.writePosixFilePermissions(from.readPosixFilePermissions())
  }

  void execute(List<String> command) {
    def proc = command.execute()
    def out = proc.in.text
    def err = proc.err.text
    proc.waitFor()
    def exitValue = proc.exitValue()
    if (exitValue != 0) {
      throw new ExitException("$out\n\n$err")
    }
  }

  Path extractImages(Path path) {
    println "  Extracting images from ${path.fileName}"
    def name = "${fileNameWithoutExtension(path)}-extracted"
    def targetDirectory = Paths.get(name).toAbsolutePath()
    Files.createDirectories(targetDirectory)
    if (Files.list(targetDirectory).toList().isEmpty()) {
      execute(['gs', '-dNOPAUSE' , '-dBATCH', '-sDEVICE=png16m', "-sOutputFile=\"${targetDirectory.toString()}/%05d.png\"", '-r600', path.fileName.toString()])
    }
    targetDirectory
  }

  String fileExtension(Path path) {
    def name = path.fileName.toString()
    name[name.lastIndexOf('.')+1..-1]
  }

  String fileNameWithoutExtension(Path path) {
    fileNameWithoutExtension(path.fileName.toString())
  }

  String fileNameWithoutExtension(String name) {
    name[0..name.lastIndexOf('.')-1]
  }

  Path firstWithExtension(Map opts=[:], Path directory, String extension) {
    def exclude = opts.exclude ?: []
    Files.list(directory).toList().find { (fileExtension(it) == extension) && (it.toAbsolutePath() !in exclude) }
  }

  List<String> convertCommand(Map opts) {
    def target = opts.target
    def compressionOptions = []
    if (opts.target.extension == 'webp') {
      def quality = opts.quality
      if (quality == 'lossless') compressionOptions = ['-define', 'webp:lossless=true']
      else compressionOptions = ['-quality', "${quality}%"]
    }
    ['convert', '-alpha', 'flatten', opts.source.toString(), '-fuzz', '7%', '-trim', '+repage', '-resize', '2700>x2700>', '+repage'] + compressionOptions + [target.toString()]
  }

  Path trimAll(Map opts=[:], Path sourceDirectory) {
    def trimCount = opts.trimCount
    assert trimCount != null
    def actionName = trimCount > 0 ? 'Trimming' : 'Resizing'
    def compression = opts.compression ?: 'webp'
    println "  $actionName images in ${sourceDirectory.fileName}"
    def readFromDirectory = sourceDirectory
    def trimDirectories = []
    for (def i = 1; i < trimCount; ++i) {
      println("    Extra trim $i")
      def iteration = i-1
      def trimDirectory = sourceDirectory.createSiblingDirectoryWithAppendix("trim-$i")
      readFromDirectory.eachFile { sourcePath ->
        def trimPath = trimDirectory.resolve(sourcePath.withExtension('webp').name)
        println("      Trimming ${sourcePath.name}")
        def command = convertCommand(source:sourcePath, target:trimPath, quality:'lossless')
        //println("        $command")
        execute(command)
      }
      trimDirectories += trimDirectory
      readFromDirectory = trimDirectory
    }
    def targetDirectory = sourceDirectory.createSiblingDirectoryWithAppendix('trimmed')
    println("    $actionName")
    readFromDirectory.eachFile { sourcePath ->
      def targetPath = targetDirectory.resolve("${fileNameWithoutExtension(sourcePath)}.$compression")
      if (!Files.exists(targetPath)) {
        println "      $actionName ${sourcePath.fileName}"
        def command = convertCommand(source:sourcePath, target:targetPath, quality:94)
        //println("        $command")
        execute(command)
      }
    }
    trimDirectories.each{it.deleteDir()}
    targetDirectory
  }

  void writeCbz(Path target, Path sourceDirectory) {
    println '  Compressing the CBZ'
    assert Files.isDirectory(sourceDirectory)
    def sourcePaths = Files.list(sourceDirectory).toList().toSorted()
    def digits = sourcePaths.size().toString().length()
    new ZipOutputStream(Files.newOutputStream(target)).withCloseable { zipOut ->
      sourcePaths.eachWithIndex { sourcePath, index ->
        def formattedIndex = String.format("%0${digits}d", index+1)
        def entryOut = new ZipEntry("${formattedIndex}.${fileExtension(sourcePath)}")
        zipOut.putNextEntry(entryOut)
        Files.newInputStream(sourcePath).withCloseable { content ->
          content.transferTo(zipOut)
        }
        zipOut.closeEntry()
      }
      zipOut.finish()
    }
  }
}

class ExitException extends Exception {
  public ExitException(String message) {
    super(message)
  }
}

/** Creates a sibling directory with a dash-separated name appended */
Path.metaClass.createDirectories = {Files.createDirectories(delegate)}
Path.metaClass.createSiblingDirectoryWithAppendix = {appendix -> delegate.siblingWithAppendix(appendix).createDirectories()}
Path.metaClass.exists = {Files.exists(delegate)}
Path.metaClass.getExtension = {delegate.name[delegate.name.lastIndexOf('.')+1..-1]}
Path.metaClass.getNameWithoutExtension = {delegate.name[0..delegate.name.lastIndexOf('.')-1]}
Path.metaClass.withExtension = {extension -> delegate.toAbsolutePath().parent.resolve("${delegate.nameWithoutExtension}.$extension")}
Path.metaClass.getName = {
  def name = delegate.toString()
  name[name.lastIndexOf('/')+1..-1]
}
Path.metaClass.readPosixFilePermissions = {Files.getPosixFilePermissions(delegate)}
/** A sibling with a dash-separated name appended */
Path.metaClass.siblingWithAppendix = {appendix -> delegate.parent.resolve("${delegate.fileName}-${appendix}")}
Path.metaClass.writePosixFilePermissions = {permissions -> Files.setPosixFilePermissions(delegate, permissions)}

try {
  def parser = new CliBuilder(usage:'pdf-to-cbz').tap {
    _ longOpt:'compression', args:1, defaultValue:'png', 'The type of image compression to use in the cbz'
    _ longOpt:'delete', 'Delete the PDF file after conversion'
    h(longOpt:'help', 'Show this message and exit')
    _ longOpt:'trims', args:1, defaultValue:'2', 'number of trims to apply'
  }
  def options = parser.parse(args)
  if (options.help) {
    parser.usage()
    System.exit(0)
  }
  new Converter().applyAll(Paths.get(''), compression:options.compression, delete:options.delete, trimCount:options.trims as Integer)
} catch (ExitException e) {
  println e.message
  System.exit(1)
}

