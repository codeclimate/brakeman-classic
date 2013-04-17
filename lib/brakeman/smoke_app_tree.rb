require "brakeman/app_tree"
require "active_support/core_ext"
require "pathname"
require "grit"
require "bertrpc"
require "uri"

module Brakeman
  class SmokeAppTree < AppTree
    class GitTree
      def initialize(uri)
        @uri = uri
      end

      def read_blob(blob_id)
        grit_repo.blob(blob_id).data
      end

      def contents
        tree_id = commit.tree.id
        output = grit_repo.git.native(:ls_tree, { r: true }, tree_id)
        grit_tree = ::Grit::Tree.allocate.construct_initialize(grit_repo, tree_id, output)
        grit_tree.contents
      end

    private

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
    end

    attr_writer :git_tree

    def initialize(url, skip_files = nil)
      uri = URI.parse(url)
      uri_parts = uri.path.sub(/^\//, "").split("/")

      @git_tree = GitTree.new(uri)
      @skip_files = skip_files
      @prefix = uri_parts[3..-1].to_a.join("/")
    end

    def valid?
      exists?("config/environment.rb")
    end

    def expand_path(path)
      raise "TODO expand_path"
    end

    def read(path)
      @git_tree.read_blob(file_index[apply_prefix(path)])
    end

    def read_path(path)
      read(path)
    end

    def path_exists?(path)
      raise "TODO path_exists?"
    end

    def exists?(path)
      file_index[apply_prefix(path)]
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

    def apply_prefix(path)
      if @prefix.to_s.size > 0
        File.join(@prefix, path)
      else
        path
      end
    end

    def find_paths(directory, extensions = "*.rb")
      all_paths = glob("#{directory}/**/#{extensions}") +
        glob("#{directory}/#{extensions}")

      all_paths.sort.uniq.tap do |paths|
        reject_skipped_files(paths)
      end
    end

    def glob(pattern)
      matching_paths = file_index.keys.select do |path|
        File.fnmatch(apply_prefix(pattern), path)
      end
      matching_paths.map { |path| remove_prefix(path) }
    end

    def remove_prefix(path)
      if @prefix.size > 0
        Pathname.new(path).relative_path_from(Pathname.new(@prefix)).to_s
      else
        path
      end
    end

    def file_index
      @file_index ||= Hash.new.tap do |index|
        @git_tree.contents.each do |content|
          index[content.name] = content.id
        end
      end
    end

    class SmokeClient
      DEFAULT_TIMEOUT = 20

      def initialize(uri, timeout = nil)
        @uri = uri
        @timeout = timeout
      end

      def method_missing(remote_method_name, *args)
        start_time = Time.now
        result = mod.send(remote_method_name, repo_id.to_s, *args)
        duration = ((Time.now - start_time) * 1_000).round
        SmokeInstrumentation.call(remote_method_name, duration)
        result
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

    class SmokeInstrumentation

      def self.runtime=(value)
        @runtime = value
      end

      def self.runtime
        @runtime ||= 0
      end

      def self.call_count=(value)
        @smoke_call_count = value
      end

      def self.call_count
        @smoke_call_count ||= 0
      end

      def self.call(remote_method_name, duration)
        return unless $statsd
        self.runtime += duration
        self.call_count += 1
        $statsd.timing    "worker.brakeman.smoke.time", duration
        $statsd.timing    "worker.brakeman.smoke.#{remote_method_name}.time", duration
        $statsd.increment "worker.brakeman.smoke.calls"
        $statsd.increment "worker.brakeman.smoke.#{remote_method_name}.calls"
      end
    end

  end
end
