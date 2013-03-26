module Brakeman
  class AppTree
    VIEW_EXTENSIONS = %w[html.erb html.haml rhtml js.erb html.slim]

    attr_reader :root

    def self.from_options(options)
      # Convert files into Regexp for matching
      if options[:skip_files]
        skip_files = "(?:" << options[:skip_files].map { |f| Regexp.escape f }.join("|") << ")$"
        skip_files = Regexp.new(skip_files)
      else
        skip_files = nil
      end

      root = if options[:app_path] =~ /^bertrpc:\/\//
        require "brakeman/smoke_app_tree"
        SmokeAppTree.new(options[:app_path], skip_files)
      else
        new(File.expand_path(options[:app_path]), skip_files)
      end
    end

    def initialize(root, skip_files = nil)
      @root = root
      @skip_files = skip_files
    end

    def valid?
      @root && exists?("app")
    end

    def expand_path(path)
      File.expand_path(path, @root)
    end

    def read(path)
      File.read(File.join(@root, path))
    end

    # This variation requires full paths instead of paths based
    # off the project root. I'd prefer to get all the code outside
    # of AppTree using project-root based paths (e.g. app/models/user.rb)
    # instead of full paths, but I suspect it's an incompatible change.
    def read_path(path)
      File.read(path)
    end

    def exists?(path)
      File.exists?(File.join(@root, path))
    end

    # This is a pair for #read_path. Again, would like to kill these
    def path_exists?(path)
      File.exists?(path)
    end

    def initializer_paths
      @initializer_paths ||= find_paths("config/initializers")
    end

    def controller_paths
      @controller_paths ||= find_paths("app/controllers")
    end

    def model_paths
      @model_paths ||= find_paths("app/models")
    end

    def template_paths
      @template_paths ||= find_paths("app/views", "*.{#{VIEW_EXTENSIONS.join(",")}}")
    end

    def layout_exists?(name)
      pattern = "#{@root}/app/views/layouts/#{name}.html.{erb,haml,slim}"
      !Dir.glob(pattern).empty?
    end

    def lib_paths
      @lib_files ||= find_paths("lib")
    end

  private

    def find_paths(directory, extensions = "*.rb")
      pattern = @root + "/#{directory}/**/#{extensions}"

      Dir.glob(pattern).sort.tap do |paths|
        reject_skipped_files(paths)
      end
    end

    def reject_skipped_files(paths)
      return unless @skip_files
      paths.reject! { |f| @skip_files.match f }
    end

  end
end
