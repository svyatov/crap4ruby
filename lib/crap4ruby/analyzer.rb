# frozen_string_literal: true

module Crap4Ruby
  # Finds explicit Ruby method definitions without executing source code.
  class Analyzer
    # Analyzes method bodies and parameter defaults with Prism.
    #
    # @param source [String] Ruby source text
    # @param path [String] source label used in results and parse errors
    # @return [Array<MethodInfo>] methods in traversal order, including nested definitions
    # @raise [Error] if source cannot be parsed
    # @example Analyze a method without loading it
    #   Analyzer.new.call("def eligible?(age) = age >= 18", path: "person.rb")
    def call(source, path:)
      result = Prism.parse(source)
      unless result.success?
        error = result.errors.first
        raise Error, "#{path}:#{error.location.start_line}: #{error.message}"
      end
      discover(result.value, [], false, path)
    end

    private

    # Tracks lexical owners; skips owners that cannot be resolved statically.
    #
    # @param node [Prism::Node, nil] subtree to visit
    # @param scope [Array<String>] lexical namespace components
    # @param singleton [Boolean] whether definitions belong to a singleton class
    # @param path [String] source label
    # @return [Array<MethodInfo>] discovered method definitions
    def discover(node, scope, singleton, path)
      return [] unless node

      case node
      when Prism::ClassNode, Prism::ModuleNode
        owner = qualify(node.constant_path, scope, declaration: true)
        owner ? discover(node.body, owner, false, path) : []
      when Prism::SingletonClassNode
        owner = node.expression.is_a?(Prism::SelfNode) ? scope : qualify(node.expression, scope)
        owner ? discover(node.body, owner, true, path) : []
      when Prism::DefNode
        discover_method(node, scope, singleton, path)
      else
        node.compact_child_nodes.flat_map { |child| discover(child, scope, singleton, path) }
      end
    end

    # Measures a definition independently from definitions nested within it.
    #
    # @param node [Prism::DefNode] method definition
    # @param scope [Array<String>] lexical namespace components
    # @param singleton [Boolean] whether the enclosing scope is a singleton class
    # @param path [String] source label
    # @return [Array<MethodInfo>] this method and its nested definitions
    def discover_method(node, scope, singleton, path)
      owner = node.receiver && !node.receiver.is_a?(Prism::SelfNode) ? qualify(node.receiver, scope) : scope
      return [] unless owner

      name = "#{'self.' if singleton || node.receiver}#{node.name}"
      lines = body_lines(node.body)
      complexity = 1 + decisions(node.parameters) + decisions(node.body)
      [MethodInfo.new(name, owner.empty? ? "Object" : owner.join("::"), complexity, lines, path)] +
        discover(node.body, scope, singleton, path)
    end

    # Resolves constant syntax without looking up runtime constants.
    # Declarations append names; references can reuse a lexical ancestor.
    #
    # @param node [Prism::Node, nil] namespace expression
    # @param scope [Array<String>] lexical namespace components
    # @param declaration [Boolean] whether the expression declares a namespace
    # @return [Array<String>, nil] qualified components, or nil for dynamic expressions
    def qualify(node, scope, declaration: false)
      case node
      when Prism::ParenthesesNode
        qualify(node.body, scope)
      when Prism::ConstantReadNode
        name = node.name.to_s
        ancestor = scope.rindex(name) unless declaration
        ancestor ? scope.take(ancestor + 1) : scope + [name]
      when Prism::ConstantPathNode
        # @type var parent: Array[String]?
        parent = node.parent ? qualify(node.parent, scope) : []
        parent&.+([node.name.to_s])
      end
    end

    # Counts branch operations, including safe navigation, outside nested definitions.
    #
    # @param node [Prism::Node, nil] subtree to measure
    # @return [Integer] number of decisions, excluding the method's base complexity
    def decisions(node)
      return 0 unless node
      return 0 if boundary?(node)

      decision = [:if_node, :unless_node, :while_node, :until_node, :for_node,
        :when_node, :in_node, :rescue_node, :rescue_modifier_node, :and_node, :or_node].include?(node.type) ||
        node.type.to_s.match?(/_(?:and|or)_write_node\z/)
      count = decision ? 1 : 0
      case node
      when Prism::CallNode, Prism::CallAndWriteNode, Prism::CallOrWriteNode,
          Prism::CallOperatorWriteNode, Prism::CallTargetNode, Prism::IndexAndWriteNode,
          Prism::IndexOrWriteNode, Prism::IndexOperatorWriteNode, Prism::IndexTargetNode
        count += 1 if node.safe_navigation?
      end
      count + node.compact_child_nodes.sum { |child| decisions(child) }
    end

    def boundary?(node)
      [Prism::DefNode, Prism::ClassNode, Prism::ModuleNode, Prism::SingletonClassNode].any? { |type| node.is_a?(type) }
    end

    # Selects body lines without nested methods, classes, or modules.
    #
    # @param node [Prism::Node, nil] method body
    # @return [Array<Integer>] one-based source lines; empty for an absent body
    def body_lines(node)
      return [] unless node

      lines = (node.location.start_line..node.location.end_line).to_a
      excluded = [] #: Array[Integer]
      collect_boundaries(node, excluded)
      lines - excluded
    end

    def collect_boundaries(node, excluded)
      if boundary?(node)
        excluded.concat((node.location.start_line..node.location.end_line).to_a)
      else
        node.compact_child_nodes.each { |child| collect_boundaries(child, excluded) }
      end
    end
  end
end
