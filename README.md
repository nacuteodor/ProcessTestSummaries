# ProcessTestSummaries

This tool is an OS X console application which processes the TestSummaries plist file to extract the last screenshots and to generate a JUnit report xml file (as a better alternative to xcpretty tool), for the unit and UI tests written in Xcode.

## Benefits:
- parses the xcodebuild source of truth document to get the tests results in a JUnit report
- fatal errors in a test will show in the JUnit report as failure
- an output log of the UI elements interactions is attached to each test in the report
- the last screenshots are saved for each test in a separate folder and in the order they were created in test.

## Usage e.g:
ProcessTestSummaries --logsTestPath $DERIVED_DATA_PATH/Logs/Test --jUnitReportPath /$REPORTS_PATH/reports/unitTestResult.xml --screenshotsPath $LAST_SCREENSHOTS_PATH --screenshotsCount 10

## Swift supported version:
Xcode 7.3

## Please, give a star to this project if it helps you.
