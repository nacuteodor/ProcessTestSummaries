# ProcessTestSummaries

This tool is an OS X console application which processes the TestSummaries plist file to extract the last screenshots and to generate a JUnit report xml file (as a better alternative to xcpretty tool), for the unit and UI tests written in Xcode.

## Benefits:
- parses the xcodebuild source of truth document to get the tests results in a JUnit report
- if a test fails with a fatal error, that will still appear in the JUnit report as failure
- an output log of the UI elements interactions is attached to each failed test in the report
- the last screenshots are saved for each test in a separate folder and in the order they were created in test
- the generated files can be easily added as artifacts in Jenkins for the tests job

## Usage e.g:
xcodebuild -derivedDataPath $DERIVED_DATA_PATH 

ProcessTestSummaries --logsTestPath $DERIVED_DATA_PATH/Logs/Test --jUnitReportPath $REPORTS_PATH/unitTestResult.xml --screenshotsPath $LAST_SCREENSHOTS_PATH --screenshotsCount 10

## Swift supported version:
Xcode 7.3

## Please, give a star to this project if it helps you.
