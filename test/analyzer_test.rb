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

    assert_equal([
      ["total", "Shop::Order"], ["self.build", "Shop::Order"],
      ["self.find", "Shop::Order"], ["save", "Other::Record"],
      ["run", "Shop::Admin::Tools"], ["self.fetch", "Shop::Order"]
    ], methods.map { |method| [method.name, method.namespace] })
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

    assert_equal 8, method.complexity
  end

  def test_preserves_reference_iteration_syntax_rules
    method = analyze(<<~RUBY).first
      def iterate(items, callback)
        items.map
        items.map(&:to_s)
        items.each.with_index { |item, index| item.to_s }
        items.each { _1.to_s }
        items.map { it.to_s }
        items.bsearch { |item| item > 0 }
        items.fetch(:missing) { :fallback }
        items.tap { |item| item.to_s }
        items.map(&callback)
      end
    RUBY

    assert_equal 6, method.complexity
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

    assert_equal 10, method.complexity
  end

  def test_omits_post_test_loop_increments_but_counts_their_predicates
    method = analyze(<<~RUBY).first
      def repeat(flag)
        begin
          work
        end while flag && ready
        begin
          work
        end until flag || done
      end
    RUBY

    assert_equal 3, method.complexity
  end

  def test_counts_nested_method_decisions_but_excludes_their_coverage_lines
    methods = analyze(<<~RUBY)
      def outer
        def inner(x)
          x ? 1 : 0
        end
        true
      end
    RUBY

    assert_equal %w[outer inner], methods.map(&:name)
    assert_equal [2, 2], methods.map(&:complexity)
    assert_equal [[5], [3]], methods.map(&:lines)
  end

  def test_rejects_invalid_source_with_its_location
    error = assert_raises(Crap4Ruby::Error) { analyze("def broken(\n") }
    assert_match(%r{lib/sample\.rb:\d+}, error.message)
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

  def test_counts_boolean_assignments_for_each_ruby_target
    method = analyze(<<~RUBY).first
      define_method(:update) do
        local &&= true
        local ||= false
        @instance &&= true
        @instance ||= false
        @@class_variable &&= true
        @@class_variable ||= false
        $global &&= true
        $global ||= false
        Constant &&= true
        Constant ||= false
        Owner::Constant &&= true
        Owner::Constant ||= false
        object.value &&= true
        object.value ||= false
        object[0] &&= true
        object[0] ||= false
      end
    RUBY

    assert_equal 17, method.complexity
  end

  def test_discounts_repeated_safe_navigation_until_local_assignment
    method = analyze(<<~RUBY).first
      def update(value, other)
        value&.first
        value&.second
        value = other
        value&.third
        value&.fourth
        receiver&.first
        receiver&.second
      end
    RUBY

    assert_equal 5, method.complexity
  end

  def test_resets_safe_navigation_for_compound_multiple_and_loop_assignments
    method = analyze(<<~RUBY).first
      def update(value, other)
        value&.first
        value ||= other
        value&.second
        value &&= other
        value&.third
        value += other
        value&.fourth
        value, other = [other, value]
        value&.fifth
        *value, other = [other, value]
        value&.after_splat
        for value in []
          value&.sixth
        end
        value = value&.seventh
        value&.eighth
      end
    RUBY

    assert_equal 12, method.complexity
  end

  def test_pattern_and_regexp_bindings_do_not_reset_safe_navigation
    method = analyze(<<~RUBY).first
      def bind(value, other, text)
        value&.first
        other in [value]
        value&.second
        other => [value]
        value&.third
        /(?<value>.+)/ =~ text
        value&.fourth
      end
    RUBY

    assert_equal 2, method.complexity
  end

  def test_visits_unless_else_before_the_main_body_for_reference_discounts
    method = analyze(<<~RUBY).first
      def update(value, other, condition)
        unless condition
          value = other
        else
          value&.first
        end
        value&.second
      end
    RUBY

    assert_equal 4, method.complexity
  end

  def test_visits_pattern_before_guard_without_counting_the_guard_wrapper
    methods = analyze(<<~RUBY)
      def first(value, other, input)
        case input
        in ^(value = other) if value&.first
          value&.second
        end
      end
      def second(value, other, input)
        case input
        in ^(value&.first) unless (value = other)
          value&.second
        end
      end
      def third(input)
        case input
        in [value] if value && ready
          value
        end
      end
    RUBY

    assert_equal [3, 4, 3], methods.map(&:complexity)
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

    assert_equal([["self.build", "Widget"], ["self.find", "Shop::Order"], ["nested", "Shop::Shop"]],
      methods.map { |method| [method.name, method.namespace] })
  end

  def test_excludes_decisions_in_parameter_defaults
    method = analyze("def choose(value = flag ? 1 : 2)\n value\nend").first

    assert_equal 1, method.complexity
    assert_equal [2], method.lines
  end

  def test_finds_nested_methods_in_parameter_defaults
    methods = analyze(<<~RUBY)
      class Sample
        def outer(value = (def inner(flag)
                            flag ? :yes : :no
                          end))
          value
        end
      end
    RUBY

    assert_equal([["outer", "Sample", 1, [5]], ["inner", "Sample", 2, [3]]],
      methods.map { |method| [method.name, method.namespace, method.complexity, method.lines] })
  end

  def test_finds_methods_in_superclass_expressions_in_the_surrounding_scope
    methods = analyze(<<~RUBY)
      module Container
        class Sample < (def parent(flag)
                          flag ? Object : BasicObject
                        end; Object)
          def child = true
        end
      end
    RUBY

    assert_equal([["parent", "Container", 2], ["child", "Container::Sample", 1]],
      methods.map { |method| [method.name, method.namespace, method.complexity] })
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

  def test_finds_literal_define_method_blocks_and_their_nested_definitions
    methods = analyze(<<~RUBY)
      module Shop
        define_method(:pick) do |value = (flag ? 1 : 2)|
          value ? :yes : :no
        end
        class << self
          define_method("build") { _1 ? :yes : :no }
        end
        define_method(:implicit) { it ? :yes : :no }
        define_method(dynamic_name) { :skip }
        self.define_method(:explicit_receiver) { :skip }
        define_method(:no_block, method(:pick))
        define_method(:outer) do
          define_method(:inner) do
            flag ? :yes : :no
          end
          true
        end
      end
    RUBY

    assert_equal([["pick", "Shop", 2], ["self.build", "Shop", 2], ["implicit", "Shop", 2],
      ["outer", "Shop", 2], ["inner", "Shop", 2]],
      methods.map { |method| [method.name, method.namespace, method.complexity] })
    assert_equal [[3], nil, nil, [16], [14]], methods.map(&:lines)
  end
end
