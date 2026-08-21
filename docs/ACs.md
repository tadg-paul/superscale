# Acceptance Criteria

This is the canonical spec. ACs introduced from 2026-08-21 onward live here.
Pre-cutover ACs remain in their originating issues until cited or migrated.

Last migrated: AC80.5 from #80 on 2026-08-21

---

## Test layout

### AC80.1 - Tests belonging to the one-off package are outside the regression command's scope.
- Introduced: #80 (closed 2026-08-21)
- Migrated: 2026-08-21
- Tests:
  - ✅ OT-80.1: the main package's enumerated test list contains no test from the one-off package
  - ✅ OT-80.2: the main package's enumerated test list contains the release-inspector regression test that shared a file with the relocated one-off test

### AC80.2 - The one-off command's test scope contains the relocated one-off tests.
- Introduced: #80 (closed 2026-08-21)
- Migrated: 2026-08-21
- Tests:
  - ✅ OT-80.3: the one-off package's enumerated test list contains the relocated one-off test
  - ✅ OT-80.4: the one-off package's tests pass when run
  - ✅ OT-80.9: the one-off command scoped to an issue with no one-off tests reports no match rather than passing silently
  - ✅ OT-80.11: the one-off command scoped to the relocated test's issue number selects that test

### AC80.3 - A one-off test added to the one-off package remains outside the regression scope while the regression command is unedited.
- Introduced: #80 (closed 2026-08-21)
- Migrated: 2026-08-21
- Tests:
  - ✅ OT-80.5: in a synthetic two-package fixture, a one-off test added to the one-off package is absent from the main package's enumerated test list
  - ✅ OT-80.6: the same synthetic one-off test is present in the one-off package's enumerated test list

### AC80.4 - The regression suite retains every regression test present before the relocation.
- Introduced: #80 (closed 2026-08-21)
- Migrated: 2026-08-21
- Tests:
  - ✅ OT-80.7: the post-relocation regression test-name set equals the pre-relocation set, captured before any relocation, less exactly the relocated one-off tests
  - ✅ OT-80.8: the regression command's own run passes with zero failures, no new warnings, and no one-off test among the tests it executed

### AC80.5 - The regression command halts when any main-package test bears a one-off identifier.
- Introduced: #80 (closed 2026-08-21)
- Migrated: 2026-08-21
- Tests:
  - ✅ RT-80.1: the guard halts on a package containing a test that bears a one-off identifier
  - ✅ RT-80.2: the guard proceeds on a package whose tests bear no one-off identifier
  - ✅ RT-80.3: the guard proceeds on a package containing a test name that holds the identifier letters without forming one
  - ✅ OT-80.10: the regression command halts when pointed at a synthetic package containing a misplaced one-off test
  - ✅ OT-80.12: the regression command proceeds when pointed at a clean synthetic package

**Key:** ✅ passing · ⏳ pending · ❌ failing · ~~🚫 removed~~
