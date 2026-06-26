# test-file-pattern.sh — canonical regex matching unit/e2e/spec test file paths.
#
# Sourced (not executed) by:
#   - diff-scale.sh        → exclude tests from the scale measure (LINES/DIRS)
#   - review-prep-diff.sh  → detect testFiles → adds the TestHygiene lens
#
# Single source of truth so the two never diverge on "what is a test file".
# Matches git-root-relative paths (ERE; use with `grep -E`).
TEST_PATTERN='(^|/)(tests?|__tests__|spec|specs|e2e|androidTest|unitTest|E2ETests?)/|(\.|_)(test|spec)\.[^/]+$|_test\.go$|Tests?\.(swift|kt|java|cs|m|mm)$|Spec\.swift$|(^|/)test_[^/]+\.py$'
