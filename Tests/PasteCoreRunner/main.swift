import Foundation

let harness = TestHarness()

runCaptureRulesTests(harness)
runHistoryStoreTests(harness)
runPersistenceTests(harness)
runSearchFilterTests(harness)
runRichTextStyleTests(harness)
runTextEditTests(harness)
runHotkeyShortcutTests(harness)

harness.finish()
