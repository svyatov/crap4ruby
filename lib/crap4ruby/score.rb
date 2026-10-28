# frozen_string_literal: true

module Crap4Ruby
  module Score
    def self.call(method, coverage)
      fraction = coverage&.fraction(method)
      crap = method.complexity * method.complexity * (1 - fraction)**3 + method.complexity if fraction
      Entry.new(method.name, method.namespace, method.complexity, fraction && fraction * 100, crap, method.path)
    end
  end
end
