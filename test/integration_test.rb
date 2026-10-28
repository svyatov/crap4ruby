# frozen_string_literal: true

require_relative "test_helper"
require "open3"

class IntegrationTest < Minitest::Test
  def with_coverage(source, invocation)
    Dir.mktmpdir("crap4ruby-integration") do |root|
      FileUtils.mkdir_p(File.join(root, "lib"))
      File.write(File.join(root, "lib/sample.rb"), source)
      File.write(File.join(root, "test.rb"), <<~RUBY)
        require "simplecov"
        SimpleCov.start
        SimpleCov.formatters = []
        require_relative "lib/sample"
        #{invocation}
      RUBY
      output, error, status = Open3.capture3(RbConfig.ruby, "test.rb", chdir: root)

      assert status.success?, "#{output}\n#{error}"
      yield root
    end
  end

  def test_scores_executable_interpolations_in_a_final_heredoc
    source = <<~'RUBY'
      def sample(flag)
        <<~TEXT
          #{if flag
              :yes
            else
              :no
            end}
        TEXT
      end
    RUBY
    with_coverage(source, "sample(true)") do |root|
      executable = File.expand_path("../exe/crap4ruby", File.dirname(__FILE__))
      library = File.expand_path("../lib", File.dirname(__FILE__))
      output, error, status = Open3.capture3(RbConfig.ruby, "-I", library, executable,
        "--threshold", "2", chdir: root)

      assert_equal 2, status.exitstatus, "#{output}\n#{error}"
      assert_match(/sample\s+Object\s+2\s+66.7%\s+2.1/, output)
      assert_includes File.read(File.join(root, ".metrics/crap.edn")), ":coverage 66.6667, :crap 2.1481"
    end
  end

  def test_excludes_nested_method_heredocs_from_outer_coverage
    source = <<~'RUBY'
      def outer(flag)
        flag.to_s
        <<~OUTER
          #{def inner(value) = <<~INNER
            #{if value
                :yes
              else
                :no
              end}
          INNER
          }
          #{flag ? :outer_yes : :outer_no}
        OUTER
      end
    RUBY
    with_coverage(source, "outer(true)") do |root|
      executable = File.expand_path("../exe/crap4ruby", File.dirname(__FILE__))
      library = File.expand_path("../lib", File.dirname(__FILE__))
      output, error, status = Open3.capture3(RbConfig.ruby, "-I", library, executable, chdir: root)

      assert_equal 0, status.exitstatus, "#{output}\n#{error}"
      assert_match(/outer\s+Object\s+3\s+100.0%\s+3.0/, output)
    end
  end

  def test_executable_returns_usage_errors_to_the_shell
    executable = File.expand_path("../exe/crap4ruby", File.dirname(__FILE__))
    library = File.expand_path("../lib", File.dirname(__FILE__))
    output, error, status = Open3.capture3(RbConfig.ruby, "-I", library, executable, "--unknown-option")

    assert_equal 1, status.exitstatus
    assert_empty output
    assert_includes error, "invalid option"
  end

  def test_reports_unknown_coverage_when_a_body_shares_its_definition_line
    source = <<~RUBY
      def inline(flag); flag ? :yes : :no; end
      def endless(flag) = flag ? :yes : :no
      def multiline(
        flag); flag ? :yes : :no
      end
    RUBY
    with_coverage(source, "") do |root|
      executable = File.expand_path("../exe/crap4ruby", File.dirname(__FILE__))
      library = File.expand_path("../lib", File.dirname(__FILE__))
      output, error, status = Open3.capture3(RbConfig.ruby, "-I", library, executable, chdir: root)

      assert_equal 0, status.exitstatus, "#{output}\n#{error}"
      %w[inline endless multiline].each do |name|
        assert_match(%r{#{name}\s+Object\s+2\s+N/A\s+N/A}, output)
      end
      assert_equal 3, File.read(File.join(root, ".metrics/crap.edn")).scan(":coverage nil, :crap nil").size
    end
  end

  def test_measures_implicit_rescue_bodies_without_the_definition_line
    source = <<~RUBY
      def rescued(flag)
        flag ? :yes : :no
      rescue StandardError
        :error
      end
    RUBY
    with_coverage(source, "") do |root|
      executable = File.expand_path("../exe/crap4ruby", File.dirname(__FILE__))
      library = File.expand_path("../lib", File.dirname(__FILE__))
      output, error, status = Open3.capture3(RbConfig.ruby, "-I", library, executable, chdir: root)

      assert_equal 0, status.exitstatus, "#{output}\n#{error}"
      assert_match(/rescued\s+Object\s+3\s+0.0%\s+12.0/, output)
    end
  end

  def test_measures_define_method_bodies_with_numbered_parameters
    source = <<~RUBY
      class Sample
        define_method(:called) do
          _1 ? :yes : :no
        end
        define_method(:uncalled) do
          _1 ? :yes : :no
        end
      end
    RUBY
    with_coverage(source, "Sample.new.called(true)") do |root|
      executable = File.expand_path("../exe/crap4ruby", File.dirname(__FILE__))
      library = File.expand_path("../lib", File.dirname(__FILE__))
      output, error, status = Open3.capture3(RbConfig.ruby, "-I", library, executable, chdir: root)

      assert_equal 0, status.exitstatus, "#{output}\n#{error}"
      assert_match(/called\s+Sample\s+2\s+100.0%\s+2.0/, output)
      assert_match(/uncalled\s+Sample\s+2\s+0.0%\s+6.0/, output)
    end
  end

  def test_does_not_attribute_code_after_a_definition_to_its_body
    source = <<~RUBY
      def ordinary(flag)
        flag ? :yes : :no; end; 1.to_s
      def endless(flag) =
        flag ? :yes : :no; 1.to_s
      define_method(:block) do |flag|
        flag ? :yes : :no; end; 1.to_s
    RUBY
    with_coverage(source, "") do |root|
      executable = File.expand_path("../exe/crap4ruby", File.dirname(__FILE__))
      library = File.expand_path("../lib", File.dirname(__FILE__))
      output, error, status = Open3.capture3(RbConfig.ruby, "-I", library, executable,
        "--threshold", "3", chdir: root)

      assert_equal 1, status.exitstatus, "#{output}\n#{error}"
      %w[ordinary endless block].each do |name|
        assert_match(%r{#{name}\s+Object\s+2\s+N/A\s+N/A}, output)
      end
    end
  end

  def test_accepts_a_threshold_equal_to_the_exact_score
    source = <<~RUBY
      def sample(flag)
        value = 1
        if flag
          value + 1
        else
          value - 1
          value - 2
        end
      end
    RUBY
    with_coverage(source, "sample(true)") do |root|
      executable = File.expand_path("../exe/crap4ruby", File.dirname(__FILE__))
      library = File.expand_path("../lib", File.dirname(__FILE__))
      output, error, status = Open3.capture3(RbConfig.ruby, "-I", library, executable,
        "--threshold", "2.256", chdir: root)

      assert_equal 0, status.exitstatus, "#{output}\n#{error}"
      assert_includes File.read(File.join(root, ".metrics/crap.edn")), ":coverage 60.0, :crap 2.256"
    end
  end

  def test_real_simplecov_result_distinguishes_loaded_and_called_methods
    Dir.mktmpdir("crap4ruby-integration") do |root|
      FileUtils.mkdir_p(File.join(root, "lib"))
      File.write(File.join(root, "lib/sample.rb"), <<~RUBY)
        class Sample
          def called
            :yes
          end
          def uncalled
            :no
          end
        end
      RUBY
      File.write(File.join(root, "test.rb"), <<~RUBY)
        require "simplecov"
        SimpleCov.start
        SimpleCov.formatters = []
        require_relative "lib/sample"
        raise "fixture failure" unless Sample.new.called == :yes
      RUBY
      output, error, status = Open3.capture3(RbConfig.ruby, "test.rb", chdir: root)

      assert status.success?, "#{output}\n#{error}"

      executable = File.expand_path("../exe/crap4ruby", File.dirname(__FILE__))
      library = File.expand_path("../lib", File.dirname(__FILE__))
      output, error, status = Open3.capture3(RbConfig.ruby, "-I", library, executable, chdir: root)

      assert status.success?, "#{output}\n#{error}"
      assert_match(/uncalled\s+Sample\s+1\s+0.0%\s+2.0/, output)
      assert_match(/called\s+Sample\s+1\s+100.0%\s+1.0/, output)
      snapshot = File.read(File.join(root, ".metrics/crap.edn"))

      assert_includes snapshot, ':name "uncalled", :namespace "Sample", :complexity 1, :coverage 0.0, :crap 2.0'
    end
  end
end
