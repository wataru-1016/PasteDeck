import Foundation

let harness = TestHarness()

runCaptureRulesTests(harness)
runHistoryStoreTests(harness)
runPersistenceTests(harness)
runSearchFilterTests(harness)
runRichTextStyleTests(harness)

harness.finish()
