# frozen_string_literal: true

module Crap4Ruby
  class Analyzer
    def call(source, path:)
      result = Prism.parse(source)
      unless result.success?
        error = result.errors.first
        raise Error, "#{path}:#{error.location.start_line}: #{error.message}"
      end
      discover(result.value, [], false, path)
    end

    private

    def discover(node, scope, singleton, path)
      case node
      when Prism::ClassNode, Prism::ModuleNode
        owner = qualify(node.constant_path, scope, declaration: true)
        owner ? discover(node.body, owner, false, path) : []
      when Prism::SingletonClassNode
        owner = node.expression.is_a?(Prism::SelfNode) ? scope : qualify(node.expression, scope)
        owner ? discover(node.body, owner, true, path) : []
      when Prism::DefNode
        owner = node.receiver && !node.receiver.is_a?(Prism::SelfNode) ? qualify(node.receiver, scope) : scope
        return [] unless owner

        name = "#{'self.' if singleton || node.receiver}#{node.name}"
        lines = body_lines(node.body)
        complexity = 1 + decisions(node.parameters) + decisions(node.body)
        [MethodInfo.new(name, owner.empty? ? "Object" : owner.join("::"), complexity, lines, path)] +
          discover(node.body, scope, singleton, path)
      else
        node ? node.compact_child_nodes.flat_map { |child| discover(child, scope, singleton, path) } : []
      end
    end

    def qualify(node, scope, declaration: false)
      case node
      when Prism::ParenthesesNode
        qualify(node.body, scope)
      when Prism::ConstantReadNode
        name = node.name.to_s
        ancestor = scope.rindex(name) unless declaration
        ancestor ? scope.take(ancestor + 1) : scope + [name]
      when Prism::ConstantPathNode
        (node.parent ? qualify(node.parent, scope) : [])&.+([node.name.to_s])
      end
    end

    def decisions(node)
      return 0 unless node
      return 0 if boundary?(node)

      decision = [:if_node, :unless_node, :while_node, :until_node, :for_node,
        :when_node, :in_node, :rescue_node, :rescue_modifier_node, :and_node, :or_node].include?(node.type) ||
        node.type.to_s.match?(/_(?:and|or)_write_node\z/)
      count = decision ? 1 : 0
      count += 1 if node.respond_to?(:safe_navigation?) && node.safe_navigation?
      count + node.compact_child_nodes.sum { |child| decisions(child) }
    end

    def boundary?(node)
      [Prism::DefNode, Prism::ClassNode, Prism::ModuleNode, Prism::SingletonClassNode].any? { |type| node.is_a?(type) }
    end

    def body_lines(node)
      return [] unless node

      lines = (node.location.start_line..node.location.end_line).to_a
      excluded = []
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
