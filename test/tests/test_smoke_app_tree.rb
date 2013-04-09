require "test/unit"
require "ostruct"
require "minitest/mock"
require "brakeman/smoke_app_tree"

class SmokeAppTreeTest < Test::Unit::TestCase
  def setup
    @git_tree = MiniTest::Mock.new
    @git_tree.expect :contents, [OpenStruct.new(name: "Gemfile", id: "123")]
    @git_tree.expect :read_blob, "foo = 1", ["123"]

    @app_tree = Brakeman::SmokeAppTree.new("")
    @app_tree.git_tree = @git_tree
  end

  def test_read
    assert_equal "foo = 1", @app_tree.read("Gemfile")
  end

  def test_exists
    assert @app_tree.exists?("Gemfile")
    refute @app_tree.exists?("Foo")
  end

  def test_finding_paths
    @git_tree.expect :contents, [
      OpenStruct.new(name: "app/models/user.rb", id: "123"),
      OpenStruct.new(name: "app/models/project.rb", id: "def")
    ]
    assert_equal ["app/models/project.rb", "app/models/user.rb"], @app_tree.model_paths
  end

  def test_prefix
    url = "bertrc://example.com/smoke/repo_id/commit_sha/myapp"
    @app_tree = Brakeman::SmokeAppTree.new(url, nil)
    @app_tree.git_tree = @git_tree

    @git_tree.expect :contents, [
      OpenStruct.new(name: "myapp/Gemfile", id: "123"),
      OpenStruct.new(name: "myapp/app/models/user.rb", id: "123"),
      OpenStruct.new(name: "myapp/app/models/project.rb", id: "def")
    ]

    assert @app_tree.exists?("Gemfile")
    assert_equal "foo = 1", @app_tree.read("Gemfile")
    assert_equal ["app/models/project.rb", "app/models/user.rb"], @app_tree.model_paths

    @git_tree.verify
  end
end
