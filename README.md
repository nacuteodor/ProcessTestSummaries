# ProcessTestSummaries

This tool is an OS X console application which processes the TestSummaries plist file to extract the last screenshots and to generate a JUnit report xml file (as a better alternative to xcpretty tool), for the unit and UI tests written in Xcode.

## Usage e.g:
ProcessTestSummaries --logsTestPath $DERIVED_DATA_PATH/Logs/Test --jUnitReportPath /$REPORTS_PATH/reports/unitTestResult.xml --screenshotsPath $LAST_SCREENSHOTS_PATH --screenshotsCount 10

## Swift supported version:
Xcode 7.3
