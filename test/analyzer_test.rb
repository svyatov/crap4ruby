# frozen_string_literal: true

require_relative "test_helper"

class AnalyzerTest < Minitest::Test
  def analyze(source)
    Crap4Ruby::Analyzer.new.call(source, path: "lib/sample.rb")
  end

  def test_finds_a_method_without_executing_source
    methods = analyze("raise 'do not execute'; def greet(name)\n name\nend")

    assert_equal 1, methods.size
    method = methods.first
    assert_equal ["greet", "Object", 1, [2], "lib/sample.rb"],
      [method.name, method.namespace, method.complexity, method.lines, method.path]
  end

  def test_resolves_namespaces_and_singleton_methods
    methods = analyze(<<~RUBY)
      module Shop
        class Order
          private def total = 1
          def self.build = new
          class << self
            def find = nil
          end
        end
        class ::Other::Record
          def save = true
        end
        module Admin::Tools
          def run = nil
        end
      end
      def (Shop::Order).fetch = nil
    RUBY

    assert_equal [
      ["total", "Shop::Order"], ["self.build", "Shop::Order"],
      ["self.find", "Shop::Order"], ["save", "Other::Record"],
      ["run", "Shop::Admin::Tools"], ["self.fetch", "Shop::Order"]
    ], methods.map { |method| [method.name, method.namespace] }
  end

  def test_counts_decisions_inside_blocks_and_lambdas
    method = analyze(<<~RUBY).first
      def choose(items, fallback)
        items.map do |item|
          next if item.nil?
          item&.value || fallback
        end
        ->(x) { x ? 1 : 0 }
        fallback &&= true
        fallback ||= false
      end
    RUBY

    assert_equal 7, method.complexity
  end

  def test_counts_loop_case_pattern_and_rescue_decisions
    method = analyze(<<~RUBY).first
      def work(value)
        while value; break; end
        until value; break; end
        for x in []; x; end
        case value
        when 1, 2 then true
        when 3 then false
        else nil
        end
        case value
        in [x] if x > 0 then x
        in {} then nil
        end
        value rescue nil
      rescue ArgumentError, TypeError
        nil
      rescue StandardError
        false
      end
    RUBY

    assert_equal 12, method.complexity
  end

  def test_separates_nested_methods_and_excludes_their_coverage_lines
    methods = analyze(<<~RUBY)
      def outer
        def inner(x)
          x ? 1 : 0
        end
        true
      end
    RUBY

    assert_equal ["outer", "inner"], methods.map(&:name)
    assert_equal [1, 2], methods.map(&:complexity)
    assert_equal [[5], [3]], methods.map(&:lines)
  end

  def test_rejects_invalid_source_with_its_location
    error = assert_raises(Crap4Ruby::Error) { analyze("def broken(\n") }
    assert_match(/lib\/sample\.rb:\d+/, error.message)
  end

  def test_ignores_keywords_in_comments_and_strings_and_handles_empty_methods
    methods = analyze(<<~RUBY)
      # if while rescue
      def message = "if && || rescue for"
      def empty
      end
      def select(value)
        if value
          1
        elsif !value
          2
        else
          3
        end
        value unless value.nil?
        value and false or true
      end
    RUBY

    assert_equal [1, 1, 6], methods.map(&:complexity)
    assert_equal [], methods[1].lines
  end

  def test_counts_safe_navigation_in_compound_assignments
    method = analyze("def update(object)\n object&.value ||= 1\nend").first
    assert_equal 3, method.complexity
  end

  def test_resolves_constant_singleton_classes_and_qualified_self_references
    methods = analyze(<<~RUBY)
      class Widget; end
      class << Widget
        def build = true
      end
      module Shop
        class Shop::Order
          def Order.find = true
        end
        class Shop
          def nested = true
        end
      end
    RUBY

    assert_equal [["self.build", "Widget"], ["self.find", "Shop::Order"], ["nested", "Shop::Shop"]],
      methods.map { |method| [method.name, method.namespace] }
  end

  def test_counts_decisions_in_parameter_defaults
    method = analyze("def choose(value = flag ? 1 : 2)\n value\nend").first
    assert_equal 2, method.complexity
    assert_equal [2], method.lines
  end

  def test_skips_dynamic_namespace_subtrees_without_executing_them
    methods = analyze(<<~RUBY)
      class factory::Thing
        class Child
          def hidden = true
        end
      end
      class Known
        def visible = true
      end
    RUBY
    assert_equal ["visible"], methods.map(&:name)
  end
end
