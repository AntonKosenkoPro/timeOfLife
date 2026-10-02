## 1. Timeless copy (EN + RU)

- [x] 1.1 Rewrite `entry.deleteMessage` (en) to timeless "You can shake to undo."; rewrite `delete.category.message` (en) the same way
- [x] 1.2 Rewrite both RU twins to "Отменить можно встряской." (same keys, no new keys; U4 both locales)
- [x] 1.3 Update `LocalizationTests.swift:173` snapshot to the four timeless values; confirm no `String+Localized.swift` key change is needed

## 2. Spec and FURPS sync

- [x] 2.1 Fold the delta spec (`specs/category-management/spec.md`) wording check: requirement body + push-commit scenario + timeless-copy scenario agree with `UndoBufferStore` earliest-of semantics
- [x] 2.2 Add the FURPS `Activity_Catalog_and_Categories.md` R3 pointer note (no R3 behavior rewrite)

## 3. Verification

- [x] 3.1 Run the iOS test suite (localization snapshot green) + `swiftlint lint --strict` per `docs/ios-test-loop.md`
- [x] 3.2 Re-check `Requirements/FURPS/Activity_Catalog_and_Categories.md` R3 and the `entry-editor`/`local-first-store` baselines for wording conflicts
- [ ] 3.3 Manual EN + RU check: both delete confirmations show the timeless sentence with no lifetime bound
