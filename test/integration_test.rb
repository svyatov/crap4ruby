# frozen_string_literal: true

require_relative "test_helper"
require "open3"

class IntegrationTest < Minitest::Test
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

      executable = File.expand_path("../exe/crap4ruby", __dir__)
      library = File.expand_path("../lib", __dir__)
      output, error, status = Open3.capture3(RbConfig.ruby, "-I", library, executable, chdir: root)
      assert status.success?, "#{output}\n#{error}"
      assert_match(/uncalled\s+Sample\s+1\s+0.0%\s+2.0/, output)
      assert_match(/called\s+Sample\s+1\s+100.0%\s+1.0/, output)
      snapshot = File.read(File.join(root, ".metrics/crap.edn"))
      assert_includes snapshot, ':name "uncalled", :namespace "Sample", :complexity 1, :coverage 0.0, :crap 2.0'
    end
  end
end
