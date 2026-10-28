# Scoring correctness audit

Audited 2026-10-28 at commit `0f88ceef5a6e9530487428392e9d698635a1b37f`.

## Follow-up implementation

The working tree now implements the selected O1 and O6 policies. The original findings below describe the audited commit, before these changes.

1. F1: Fixed heredoc descendant ranges, including exclusion of nested method heredocs from enclosing coverage.
2. F2: Shared declaration lines and body lines with trailing code after the definition now produce unknown coverage. Unknown scores pass a threshold only when `CC^2 + CC` fits it. Otherwise, the check exits 1; measured violations retain exit 2.
3. F3: Coverage fractions, scores, and decimal threshold comparisons retain exact rational arithmetic. Display rounding does not affect the result.
4. F4: Explicit definitions inside parameter defaults and superclass expressions are discovered.
5. F5: Complexity follows RuboCop 1.92.1, and literal bare `define_method` blocks are discovered. The remaining documented limits, including line coverage, runtime metaprogramming, and `.rb` source selection, still apply.

The complete repository gate passes on CRuby 3.3.11 and 4.0.9: 54 tests, 260 assertions, full static call typing, and all library CRAP scores at or below 10. An independent comparison matched 649 method results against the actual RuboCop 1.92.1 CLI. Eighteen additional deliberate scoring and output mutations were caught by regression assertions.

Independent CLI QA found and verified repairs for implicit block parameter locations, trailing-line coverage contamination, control characters in method names, and misleading rounded threshold diagnostics. The final tested source hashes match the working tree. Ruby 3.4 remains untested in this session.

These public scoring and threshold changes require a minor release. No version change or commit was made. The result remains CRAP with a documented line-coverage proxy, not original basis path measurement or an exhaustive runtime Ruby inventory.

## Result

The algebra matches the CRAP formula. The implementation cannot claim complete Ruby coverage or universally correct scores.

This audit reproduced incorrect coverage attribution, omitted explicit definitions, and a false threshold failure. Some broader limits are already documented design choices.

The relevant distinction is between formula correctness, input measurement, and source selection. Correct algebra does not correct missing methods or inaccurate coverage.

## Reproduced findings

### F1: Final heredocs can lose executable coverage lines

Severity: high. This is an implementation defect in method-body line selection.

[Analyzer#body_lines](lib/crap4ruby/analyzer.rb#L118) uses the outer node's location range. A final heredoc's outer location can end at its introducer.

The interpolation contains executable descendants outside that range:

```ruby
class Sample
  def sample(flag)
    <<~TEXT
      #{if flag
          :yes
        else
          :no
        end}
    TEXT
  end
end
```

After `Sample.new.sample(true)`, fresh SimpleCov data reports executable lines 4, 5, and 7 with hits `1, 1, 0`.

The analyzer selects only line 3, whose hit count is `nil`. Reported complexity is 2, but coverage and CRAP are N/A.

With the documented line-coverage policy, coverage should be `2/3` and CRAP should be approximately `2.148148`.

The real CLI exits 0 with `--threshold 1`, because [threshold_status](lib/crap4ruby/cli.rb#L111) ignores unknown scores.

Correction: include executable heredoc descendants when selecting body locations. Preserve exclusions for nested definitions. Add a real SimpleCov regression fixture.

### F2: Uncalled inline and endless methods can receive full coverage

Severity: high for score reliability. This is a documented measurement limitation with a demonstrated false pass.

```ruby
class Sample
  def sample(flag) = flag ? :yes : :no
end
```

Loading this file without calling `sample` gives its definition line a positive hit count.

[Coverage#fraction](lib/crap4ruby/coverage.rb#L40) interprets that line as covered method code. The report shows CC 2, coverage 100%, and CRAP 2.

The uncalled method should have coverage 0% and CRAP 6. The CLI exits 0 with `--threshold 3`.

The same issue affects `def sample; :yes; end`. Distinct methods or expressions sharing a line also cannot be separated reliably.

The [README limitation](README.md#L170) acknowledges shared lines. Documentation does not make the resulting 100% value proof of method execution.

Correction: require independent invocation evidence for ambiguous definition lines, or report their coverage as unknown. Define how unknown scores affect threshold enforcement.

### F3: Floating-point error can fail a mathematically equal threshold

Severity: medium. This is a numeric boundary defect.

With CC 2 and three covered lines out of five:

```text
Exact CRAP = 2^2 * (1 - 3/5)^3 + 2 = 2.256
Computed Float = 2.2560000000000002
Threshold = 2.256
CLI exit = 2
Snapshot CRAP = 2.256
```

This was reproduced through the real CLI using fresh SimpleCov data from this method, called with `true`:

```ruby
def sample(flag)
  value = 1
  if flag
    value + 1
  else
    value - 1
    value - 2
  end
end
```

[Coverage#fraction](lib/crap4ruby/coverage.rb#L50) converts the ratio to Float. [Score.call](lib/crap4ruby/score.rb#L14) propagates rounding, and [threshold_status](lib/crap4ruby/cli.rb#L112) compares it strictly.

Correction: define exact decimal threshold semantics and preserve sufficient numeric precision through comparison. Do not compare rounded display values.

### F4: Some explicit method definitions are omitted

Severity: medium. This contradicts the stated coverage of explicit and nested definitions.

```ruby
def outer(value = (def inner(flag)
                    flag ? :yes : :no
                  end))
  value
end
```

Ruby installs `inner` when the default expression executes. The analyzer returns only `outer`, so `inner` never receives a score.

[Analyzer#discover_method](lib/crap4ruby/analyzer.rb#L64) discovers nested definitions only in the body. It does not traverse parameter expressions for definitions.

The complexity counter does inspect parameters, but it deliberately stops at nested definitions. Therefore, the omitted method's decisions are not counted elsewhere.

A second parsed example, `class Sample < (def outer; true; end; Object); end`, returns no methods.

[Analyzer#discover](lib/crap4ruby/analyzer.rb#L38) visits a class body without visiting its superclass expression.

Correction: separate definition discovery from complexity ownership. Visit executable parameter and superclass expressions while preserving each nested method's independent score.

### F5: The metric has explicit scope and policy gaps

Severity: a contract limitation, not one isolated implementation defect.

| Area | Observed behavior | Consequence |
| --- | --- | --- |
| Iteration | `items.each { ... }` adds no point; equivalent `for` adds one. | Ruby spelling changes the score. |
| Safe navigation | Every operation adds one, including repeated operations on the same local variable. | Differs from RuboCop's repeated-receiver discount. |
| Parameter defaults | Explicit decisions count toward CC; default-expression lines do not enter coverage. | Untested defaults can accompany reported 100% coverage. |
| Method creation | Literal `define_method`, aliases, and generated accessors are excluded. | The report does not enumerate all runtime methods. |
| Dynamic ownership | Dynamic receivers and some namespace expressions are skipped. `Class.new { def sample; ...; end }` is attributed lexically to `Object`. | Ownership is not a runtime method inventory. |
| Source selection | Only `.rb` files survive [Discovery.call](lib/crap4ruby/discovery.rb#L34), even when another filename is explicit. | `.rake`, `.gemspec`, `Rakefile`, `Gemfile`, `config.ru`, and extensionless scripts are excluded. |
| Non-method code | Top-level and class/module initialization decisions receive no independent score. | Whole-program Ruby coverage is outside the metric's scope. |
| Coverage freshness | Supplied suites merge without an age cutoff or source-content identity check. | Old results can describe different source text. |
| Coverage granularity | Positive line hits define coverage; branch records are ignored. | Untested branches on executed lines can appear fully covered. |

These policies are mostly documented in the [complexity rules and limits](README.md#L116). They prevent an unrestricted claim about every Ruby construct.

Additional probes found CC 1 for a standalone `value in [Integer]` predicate and no extra point for a pattern alternative or flip-flop.

Those constructs need explicit policy decisions before calling their counts wrong. Neither the CRAP formula nor the cited ports supplies a complete Ruby specification.

## What passed

The [scoring expression](lib/crap4ruby/score.rb#L14) matches:

```text
CRAP = CC^2 * (1 - coverage_fraction)^3 + CC
```

At zero coverage it produces `CC^2 + CC`. At full coverage it produces `CC`. Percentage conversion happens after calculation.

The existing suite passed: `bundle exec rake test`, 33 tests, zero failures.

A separate 49-case parser matrix matched the README's documented counts. It covered conditionals, loops, cases, guards, rescues, boolean operators, assignments, safe navigation, blocks, lambdas, and nested boundaries.

A 49,500-case numeric grid compared scores with exact rational results. No difference exceeded `1e-8`; exact threshold equality still fails as F3 demonstrates.

Existing tests also cover suite unions, null-line exclusion, absent files, malformed reports, and separating loaded definitions from called multiline methods.

Taking the maximum hit count across suites is sufficient for covered-line union because scoring only asks whether each count is positive.

## Upstream interpretation

### Original CRAP definition

Alberto Savoia's original definition uses the same algebra, with coverage expressed as a percentage before division by 100.

It specifies basis path coverage, not line coverage. His 2011 retrospective repeats that requirement. [Original definition](https://www.artima.com/weblogs/viewpost.jsp?thread=210575), [author's retrospective](https://testing.googleblog.com/2011/02/this-code-is-crap.html).

Inference: line or branch totals do not establish which combinations of decisions were executed. Branch coverage alone would not establish original basis path coverage.

### Implementations cited by the README

The three cited ports share the formula but use different coverage proxies and counting policies:

| Implementation | Inspected commit | Coverage input |
| --- | --- | --- |
| `unclebob/crap4java` | `69b561209f130ece728f19b0001e90df5a117c3a` | JaCoCo method instruction counters. |
| `unclebob/crap4clj` | `e90be2e7aa02c2ec5d6544e9cecddc6b73ad3e4d` | Weighted Cloverage forms, with LCOV line fallback. |
| `unclebob/crap4go` | `bee16dbdadb4af927a7792083f3cba2ae58841ed` | Weighted covered statements from Go coverage segments. |

Coverage sources: [Java](https://github.com/unclebob/crap4java/blob/69b561209f130ece728f19b0001e90df5a117c3a/src/crap4java/JacocoCoverageParser.java), [Clojure](https://github.com/unclebob/crap4clj/blob/e90be2e7aa02c2ec5d6544e9cecddc6b73ad3e4d/src/crap4clj/coverage.cljc), [Go](https://github.com/unclebob/crap4go/blob/bee16dbdadb4af927a7792083f3cba2ae58841ed/internal/coverage/coverage.go).

Formula sources: [Java](https://github.com/unclebob/crap4java/blob/69b561209f130ece728f19b0001e90df5a117c3a/src/crap4java/CrapScore.java), [Clojure](https://github.com/unclebob/crap4clj/blob/e90be2e7aa02c2ec5d6544e9cecddc6b73ad3e4d/src/crap4clj/crap.cljc), [Go](https://github.com/unclebob/crap4go/blob/bee16dbdadb4af927a7792083f3cba2ae58841ed/internal/crap/crap.go).

The ports also differ in extracted units and handling absent coverage. Their implementations cannot define a single complete Ruby contract.

Some upstream README examples contain arithmetic errors. Both Go and Clojure show CC 12, coverage 45%, and CRAP 130.2; the formula gives 35.958.

Clojure also shows CC 8, coverage 82%, and CRAP 3.4. The formula gives 8.373248, and a score below CC is impossible.

Example sources: [Go README](https://github.com/unclebob/crap4go/blob/bee16dbdadb4af927a7792083f3cba2ae58841ed/README.md), [Clojure README](https://github.com/unclebob/crap4clj/blob/e90be2e7aa02c2ec5d6544e9cecddc6b73ad3e4d/README.md).

### Ruby reference policy

RuboCop `v1.92.1`, commit `aa228eb03094d66aca26664839ca14b10d76f702`, provides an established Ruby convention. CRAP does not require that convention.

Its complexity calculation counts known iteration blocks and block arguments, discounts repeated safe navigation on a local receiver, and excludes parameter-default decisions.

It counts each `when` clause once, matching this project. Its method detector also recognizes bare `define_method` calls with literal names.

Sources: [complexity counter](https://github.com/rubocop/rubocop/blob/aa228eb03094d66aca26664839ca14b10d76f702/lib/rubocop/cop/metrics/cyclomatic_complexity.rb), [iteration rules](https://github.com/rubocop/rubocop/blob/aa228eb03094d66aca26664839ca14b10d76f702/lib/rubocop/cop/metrics/utils/iterating_block.rb), [safe-navigation rules](https://github.com/rubocop/rubocop/blob/aa228eb03094d66aca26664839ca14b10d76f702/lib/rubocop/cop/metrics/utils/repeated_csend_discount.rb), [method detection](https://github.com/rubocop/rubocop/blob/aa228eb03094d66aca26664839ca14b10d76f702/lib/rubocop/cop/mixin/method_complexity.rb).

Ruby documents separate line, branch, and method coverage modes. Its documented modes do not include basis path coverage. [Ruby Coverage API](https://docs.ruby-lang.org/en/master/Coverage.html).

## Evidence scope

F1 through F4 were reproduced using CRuby 3.3.11 and 4.0.9, Prism 1.9.0, and SimpleCov 1.3.2.

F1 through F3 include actual subprocess CLI runs with freshly generated SimpleCov reports. The nested-default example also executed successfully and installed its omitted method.

The parser matrix, numeric grid, and existing suite ran on CRuby 4.0.9. Ruby 3.4 execution was not attempted after dependency checking found missing `lefthook`.

Runtime coverage instrumentation can differ between Ruby versions. The audit observed different executable-line treatment for a pattern-matching `case` header between 3.3 and 4.0.

Upstream evidence came from primary publications, documentation, and fixed GitHub revisions. Upstream programs were inspected but not executed.

Prism 1.0.0 source contains the checked call/index node classes and generates their `safe_navigation?` predicates. This was a source check, not minimum-version execution.

Sources: [Prism node schema](https://github.com/ruby/prism/blob/163a2659260c6c74d8e7e02c5431fc61d17315c1/config.yml), [Ruby node generator](https://github.com/ruby/prism/blob/163a2659260c6c74d8e7e02c5431fc61d17315c1/templates/lib/prism/node.rb.erb).

No production code, dependencies, or existing tests were changed. Temporary probe scripts were removed after recording their source examples and results here.

## Recommended sequence

1. Fix heredoc location selection and discovery of explicit definitions in executable expressions, with real coverage regressions.
2. Define ambiguous and unknown coverage behavior, including threshold enforcement, before reporting full coverage for shared definition lines.
3. Make exact threshold equality reliable with a documented numeric comparison policy.
4. Adopt and document one Ruby complexity convention, with explicit decisions for iterators, defaults, patterns, and safe navigation.
5. Describe the result as CRAP using that convention and its coverage proxy. Avoid claims of complete Ruby analysis or original basis path measurement.
