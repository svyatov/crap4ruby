# frozen_string_literal: true

module Crap4Ruby
  # Finds explicit methods and literal define_method blocks without executing code.
  class Analyzer
    # RuboCop 1.92.1 Metrics::Utils::IteratingBlock's method-name policy.
    ITERATING_METHODS = %i[
      all? any? chain chunk chunk_while collect collect_concat count cycle
      detect drop drop_while each each_cons each_entry each_slice
      each_with_index each_with_object entries filter filter_map find
      find_all find_index flat_map grep grep_v group_by inject lazy map
      max max_by min min_by minmax minmax_by none? one? partition reduce
      reject reverse_each select slice_after slice_before slice_when sort
      sort_by sum take take_while tally to_h uniq zip with_index with_object
      bsearch bsearch_index collect! combination d_permutation delete_if
      each_index keep_if map! permutation product reject! repeat
      repeated_combination select! sort! each_key each_pair each_value
      fetch fetch_values has_key? merge merge! transform_keys transform_keys!
      transform_values transform_values!
    ].freeze

    # Analyzes method bodies with Prism and the RuboCop 1.92.1 counting rules.
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
        discover_class(node, scope, singleton, path)
      when Prism::SingletonClassNode
        owner = node.expression.is_a?(Prism::SelfNode) ? scope : qualify(node.expression, scope)
        owner ? discover(node.body, owner, true, path) : []
      when Prism::DefNode
        discover_method(node, scope, singleton, path)
      when Prism::CallNode
        discover_call(node, scope, singleton, path)
      else
        node.compact_child_nodes.flat_map { |child| discover(child, scope, singleton, path) }
      end
    end

    def discover_class(node, scope, singleton, path)
      # @type var methods: Array[MethodInfo]
      methods = node.is_a?(Prism::ClassNode) ? discover(node.superclass, scope, singleton, path) : []
      owner = qualify(node.constant_path, scope, declaration: true)
      methods + (owner ? discover(node.body, owner, false, path) : [])
    end

    def discover_call(node, scope, singleton, path)
      name = defined_name(node)
      block = node.block
      if name && block.is_a?(Prism::BlockNode)
        discover_block(block, name, scope, singleton, path)
      else
        node.compact_child_nodes.flat_map { |child| discover(child, scope, singleton, path) }
      end
    end

    def discover_block(block, name, scope, singleton, path)
      raise EncodingError unless name.valid_encoding?

      name = name.encode(Encoding::UTF_8)
      parameters = block.parameters
      header = parameters.is_a?(Prism::BlockParametersNode) ? parameters.location : block.opening_loc
      lines = body_lines(block.body, after: header.end_line, ending: block.location)
      name = "self.#{name}" if singleton
      [MethodInfo.new(name, scope.empty? ? "Object" : scope.join("::"), 1 + decisions(block.body), lines, path)] +
        discover(block.parameters, scope, singleton, path) + discover(block.body, scope, singleton, path)
    rescue EncodingError
      raise Error, "#{path}:#{block.location.start_line}: define_method name must be representable in UTF-8"
    end

    def defined_name(node)
      return unless node.is_a?(Prism::CallNode) && node.name == :define_method && node.receiver.nil?
      return unless node.block.is_a?(Prism::BlockNode)

      arguments = node.arguments&.arguments
      return unless arguments && arguments.size == 1

      name = arguments.first
      name.unescaped if name.is_a?(Prism::SymbolNode) || name.is_a?(Prism::StringNode)
    end

    # Builds this method's entry and discovers nested definitions.
    #
    # @param node [Prism::DefNode] method definition
    # @param scope [Array<String>] lexical namespace components
    # @param singleton [Boolean] whether the enclosing scope is a singleton class
    # @param path [String] source label
    # @return [Array<MethodInfo>] this method and its nested definitions
    def discover_method(node, scope, singleton, path)
      owner = method_owner(node, scope)
      return [] unless owner

      name = "#{"self." if singleton || node.receiver}#{node.name}"
      header = node.equal_loc || node.rparen_loc || node.parameters&.location || node.name_loc
      lines = body_lines(node.body, after: header.end_line, ending: node.location)
      complexity = 1 + decisions(node.body)
      [MethodInfo.new(name, owner.empty? ? "Object" : owner.join("::"), complexity, lines, path)] +
        discover(node.parameters, scope, singleton, path) +
        discover(node.body, scope, singleton, path)
    end

    def method_owner(node, scope)
      node.receiver && !node.receiver.is_a?(Prism::SelfNode) ? qualify(node.receiver, scope) : scope
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

    # Counts the entire body, with RuboCop's per-method safe-navigation discount.
    #
    # @param node [Prism::Node, nil] subtree to measure
    # @return [Integer] number of decisions, excluding the method's base complexity
    # @param seen [Hash<Symbol, Boolean>] local receivers since their last assignment
    # @param target [Boolean] whether a target node belongs to an assignment
    def decisions(node, seen = {}, target: false)
      return 0 unless node

      case node
      when Prism::LocalVariableWriteNode, Prism::LocalVariableAndWriteNode,
          Prism::LocalVariableOrWriteNode, Prism::LocalVariableOperatorWriteNode
        seen.delete(node.name)
      when Prism::LocalVariableTargetNode
        seen.delete(node.name) if target
      end
      count = decision?(node) ? 1 : 0
      count += 1 if iteration?(node)
      count += 1 if safe_navigation?(node, seen)
      count + child_decisions(node, seen, target)
    end

    def child_decisions(node, seen, target)
      # RuboCop visits unless branches and guarded patterns in this order.
      if node.is_a?(Prism::UnlessNode)
        return decisions(node.predicate, seen) + decisions(node.else_clause, seen) + decisions(node.statements, seen)
      end

      if node.is_a?(Prism::InNode)
        guard = node.pattern
        if guard.is_a?(Prism::IfNode) || guard.is_a?(Prism::UnlessNode)
          return decisions(guard.statements, seen) + decisions(guard.predicate, seen) + decisions(node.statements, seen)
        end
      end
      node.compact_child_nodes.sum { |child| decisions(child, seen, target: assignment_target?(node, child, target)) }
    end

    def assignment_target?(node, child, target)
      case node
      when Prism::MultiWriteNode then child != node.value
      when Prism::MultiTargetNode, Prism::SplatNode then target
      when Prism::ForNode then child == node.index
      when Prism::RescueNode then child == node.reference
      else false
      end
    end

    def decision?(node)
      return !node.begin_modifier? if node.is_a?(Prism::WhileNode) || node.is_a?(Prism::UntilNode)

      %i[if_node unless_node for_node
        when_node in_node rescue_modifier_node and_node or_node].include?(node.type) ||
        node.type.to_s.match?(/_(?:and|or)_write_node\z/) ||
        (node.is_a?(Prism::BeginNode) && !node.rescue_clause.nil?)
    end

    def safe_navigation?(node, seen)
      case node
      when Prism::CallNode, Prism::CallAndWriteNode, Prism::CallOrWriteNode,
          Prism::CallOperatorWriteNode, Prism::CallTargetNode, Prism::IndexAndWriteNode,
          Prism::IndexOrWriteNode, Prism::IndexOperatorWriteNode, Prism::IndexTargetNode
        return false unless node.safe_navigation?

        receiver = node.receiver
        return true unless receiver.is_a?(Prism::LocalVariableReadNode)
        return false if seen[receiver.name]

        seen[receiver.name] = true
      else
        false
      end
    end

    def iteration?(node)
      return false unless node.is_a?(Prism::CallNode) && ITERATING_METHODS.include?(node.name)

      block = node.block
      return false unless block
      return true unless block.is_a?(Prism::BlockNode)

      parameters = block.parameters
      !parameters || parameters.is_a?(Prism::BlockParametersNode)
    end

    def boundary?(node)
      [Prism::DefNode, Prism::ClassNode, Prism::ModuleNode, Prism::SingletonClassNode].any? do |type|
        node.is_a?(type)
      end ||
        !defined_name(node).nil?
    end

    # Selects body lines without nested methods, classes, or modules.
    #
    # @param node [Prism::Node, nil] method body
    # @param after [Integer] last line of the method declaration
    # @param ending [Prism::Location] definition location, including its closing delimiter
    # @return [Array<Integer>, nil] body lines; nil when shared with the declaration
    def body_lines(node, after:, ending:)
      return [] unless node

      # @type var start: Prism::Node?
      start = node.is_a?(Prism::BeginNode) && !node.begin_keyword_loc ? node.compact_child_nodes.first : node
      return [] unless start
      return nil if start.location.start_line <= after

      excluded = [] #: Array[Integer]
      last_line = body_end_line(node, excluded)
      lines = (start.location.start_line..last_line).to_a - excluded
      return nil if lines.include?(ending.end_line) && trailing_code?(ending)

      lines
    end

    def trailing_code?(location)
      tail = location.slice_lines.lines.last.to_s.byteslice(location.end_column..).to_s
      !tail.match?(/\A[;\s]*(?:#|\z)/)
    end

    # Heredoc interpolations can extend beyond their parent node's location.
    def body_end_line(node, excluded)
      last_line = node.location.end_line
      node.compact_child_nodes.each do |child|
        child_line = body_end_line(child, excluded)
        last_line = child_line if child_line > last_line
      end
      excluded.concat((node.location.start_line..last_line).to_a) if boundary?(node)
      last_line
    end
  end
end
