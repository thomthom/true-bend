require 'json'
require 'pathname'

class Package < Skippy::Command

  desc 'build', 'Package the extension into an RBZ in the archive folder.'
  def build
    require 'zip'

    project = Skippy::Project.current_or_fail
    source_path = project.extension_source
    say "Extension source path: #{source_path}", :blue

    version = extension_version(project)
    say "Extension version: #{version}", :blue

    archive_path = project.path('archive')
    archive_path.mkpath

    rbz_path = archive_path.join("#{project.basename}-#{version}.rbz")
    relative_rbz_path = rbz_path.relative_path_from(project.path)

    if rbz_path.exist?
      unless yes?("Archive #{relative_rbz_path} already exists. Overwrite?")
        say "Kept the existing #{relative_rbz_path}", :yellow
        return
      end

      rbz_path.delete
    end

    Zip::File.open(rbz_path.to_s, create: true) do |zip_file|
      extension_files(source_path).each { |file|
        relative_name = file.relative_path_from(source_path).to_s
        say "Archiving: #{relative_name}"
        zip_file.add(relative_name, file.to_s)
      }
    end
    say "Created #{relative_rbz_path}", :yellow
  end
  default_command(:build)

  private

  # @param [Skippy::Project] project
  # @return [String] The version in the extension's `extension.json`.
  def extension_version(project)
    extension_json = project.extension_source.join(project.basename,
                                                   'extension.json')
    JSON.parse(extension_json.read).fetch('version')
  end

  # @param [Pathname] source_path
  # @return [Array<Pathname>] The files to package, in the same order each time.
  def extension_files(source_path)
    files = Pathname.glob(source_path.join('**', '*')).select(&:file?)
    files.sort
  end

end
