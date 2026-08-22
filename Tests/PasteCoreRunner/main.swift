import Foundation

let harness = TestHarness()

runCaptureRulesTests(harness)
runHistoryStoreTests(harness)
runPersistenceTests(harness)
runSearchFilterTests(harness)
runSearchTextTests(harness)
runFileLinkRulesTests(harness)
runRichTextStyleTests(harness)
runTextEditTests(harness)
runImageEditTests(harness)
runHotkeyShortcutTests(harness)
runNumberKeyRulesTests(harness)
runPasteRulesTests(harness)
runOCROutputFormatTests(harness)
runOCRJSONTests(harness)
runOCRTableTests(harness)
runOCRLineJoiningTests(harness)
runOCRLayoutTests(harness)
runHotkeyActionTests(harness)

harness.finish()
