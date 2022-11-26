#!/usr/bin/env groovy

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
    def name = file.fileName.toString()
    def trimmed = trimAll(file, quality:opts.quality, trimFuzzFactor:opts.trimFuzzFactor)
    def cbz = Paths.get("${name}.cbz").toAbsolutePath()
    writeCbz(cbz, trimmed)
    copyPermissions(file, cbz)
    trimmed.deleteDir()
    if (opts.delete) file.deleteDir()
  }

  void applyAll(Map opts=[:], Path directory) {
    directory.eachDir { file ->
      println "Converting ${file.fileName}"
      apply(file, delete:opts.delete, quality:opts.quality, trimFuzzFactor:opts.trimFuzzFactor)
    }
  }

  void copyPermissions(Path from, Path to) {
    GroupPrincipal group = Files.readAttributes(from, PosixFileAttributes.class, LinkOption.NOFOLLOW_LINKS).group();
    Files.getFileAttributeView(to, PosixFileAttributeView.class, LinkOption.NOFOLLOW_LINKS).setGroup(group);
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

  Path trimAll(Map opts=[:], Path sourceDirectory) {
    println '  Trimming images'
    def quality = opts.quality ?: '94'
    def targetDirectory = sourceDirectory.parent.resolve("${sourceDirectory.fileName}-trimmed")
    Files.createDirectories(targetDirectory)
    sourceDirectory.eachFile { sourcePath ->
      def targetPath = targetDirectory.resolve("${fileNameWithoutExtension(sourcePath)}.webp")
      if (!Files.exists(targetPath)) {
        println "    Trimming ${sourcePath.fileName}"
        execute(['convert', '-fuzz', "${opts.trimFuzzFactor}%", '-trim', '+repage', '-resize', '2700>x2700>', '-quality', quality, sourcePath.toString(), targetPath.toString()])
      }
    }
    targetDirectory
  }

  void writeCbz(Path target, Path sourceDirectory) {
    println '  Compressing the CBZ'
    assert Files.isDirectory(sourceDirectory)
    new ZipOutputStream(Files.newOutputStream(target)).withCloseable { zipOut ->
      Files.list(sourceDirectory).toList().toSorted().each { sourcePath ->
        def entryOut = new ZipEntry(sourcePath.fileName.toString())
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

try {
  def parser = new CliBuilder(usage:'images-to-cbz').tap {
    _ longOpt:'delete', 'Delete the image directory after conversion'
    _ longOpt:'quality', args:1, defaultValue:'94', 'Compressed image quality'
    _ longOpt:'trim-fuzz-factor', args:1, defaultValue:'7', argName:'trimFuzzFactor', 'When trimming edges, how eager to be'
  }
  def options = parser.parse(args)
  new Converter().applyAll(Paths.get('').toAbsolutePath(), delete:options.delete, quality:options.quality, trimFuzzFactor:options['trim-fuzz-factor'])
} catch (ExitException e) {
  println e.message
  System.exit(1)
}

