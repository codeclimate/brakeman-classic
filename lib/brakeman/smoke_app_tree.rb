require "brakeman/app_tree"
require "active_support/core_ext"
require "grit"
require "bertrpc"
require "uri"

module Brakeman
  class SmokeAppTree < AppTree

    def initialize(url, skip_files = nil)
      @uri = URI.parse(url)
      @skip_files = skip_files
    end

    def valid?
      true
    end

    def expand_path(path)
      raise "TODO expand_path"
    end

    def read(path)
      grit_repo.blob(file_index[path]).data
    end

    def read_path(path)
      read(path)
    end

    def path_exists?(path)
      raise "TODO path_exists?"
    end

    def exists?(path)
      file_index[path]
    end

    def template_paths
      @template_paths ||= VIEW_EXTENSIONS.map do |extension|
        find_paths("app/views", "*.#{extension}")
      end.flatten.uniq
    end

    def layout_exists?(name)
      !glob("app/views/layouts/#{name}.html.erb").empty? ||
      !glob("app/views/layouts/#{name}.html.haml").empty?
    end

  private

    def find_paths(directory, extensions = "*.rb")
      (glob("#{directory}/**/#{extensions}") +
      glob("#{directory}/#{extensions}")).uniq
    end

    def glob(pattern)
      file_index.keys.select do |path|
        File.fnmatch(pattern, path)
      end
    end

    def file_index
      @file_index ||= Hash.new.tap do |index|
        deep_tree(commit.tree.id).contents.each do |content|
          index[content.name] = content.id
        end
      end
    end

    def deep_tree(tree_id)
      output = grit_repo.git.native(:ls_tree, { r: true }, tree_id)
      ::Grit::Tree.allocate.construct_initialize(grit_repo, tree_id, output)
    end

    def commit
      @commit ||= grit_repo.commit(commit_sha)
    end

    def grit_repo
      @grit_repo ||= ::Grit::Repo.allocate.tap do |r|
        r.path = "#{repo_id}.git"
        r.git = SmokeClient.new(@uri)
      end
    end

    def repo_id
      @repo_id ||= uri_parts[1]
    end

    def commit_sha
      @commit_sha ||= uri_parts[2]
    end

    def uri_parts
      @uri_parts ||= @uri.path.sub(/^\//, "").split("/")
    end

    class SmokeClient
      DEFAULT_TIMEOUT = 20

      def initialize(uri, timeout = nil)
        @uri = uri
        @timeout = timeout
      end

      def method_missing(remote_method_name, *args)
        mod.send(remote_method_name, repo_id.to_s, *args)
      end

      def repo_id
        @repo_id ||= uri_parts[1]
      end

      def mod
        service.call.send(module_name)
      end

      def service
        @service ||= ::BERTRPC::Service.new(@uri.host, @uri.port, @timeout || DEFAULT_TIMEOUT)
      end

      def module_name
        @module_name ||= uri_parts[0]
      end

      def uri_parts
        @uri_parts ||= @uri.path.sub(/^\//, "").split("/")
      end
    end

  end
end
