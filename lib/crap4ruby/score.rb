# frozen_string_literal: true

module Crap4Ruby
  # Combines static complexity and measured coverage into CRAP scores.
  module Score
    # Calculates `complexity**2 * (1 - fraction)**3 + complexity`.
    #
    # @param method [MethodInfo] static method analysis
    # @param coverage [Coverage, nil] coverage reader, or nil to disable scoring
    # @return [Entry] result with percentage coverage; coverage and CRAP are nil
    #   when coverage is disabled or the method has no measurable lines
    def self.call(method, coverage)
      fraction = coverage&.fraction(method)
      if fraction
        # Combine integer terms before constructing the exact score.
        denominator = fraction.denominator
        uncovered = denominator - fraction.numerator
        cube = denominator * denominator * denominator
        complexity = method.complexity
        crap = Rational((complexity * complexity * uncovered * uncovered * uncovered) + (complexity * cube), cube)
      end
      Entry.new(method.name, method.namespace, method.complexity, fraction && (fraction * 100).to_f, crap, method.path)
    end
  end
end
