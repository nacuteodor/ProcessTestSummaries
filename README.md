# ProcessTestSummaries

This tool is an OS X console application which processes the TestSummaries plist file to extract the last screenshots and to generate a JUnit report xml file (as a better alternative to xcpretty tool), for the unit and UI tests written in Xcode.

## Benefits:
- parses the xcodebuild source of truth document to get the tests results in a JUnit report
- if a test fails with a fatal error, that will still appear in the JUnit report as failure
- an output log of the UI elements interactions is attached to each failed test in the report
- links to the last screeshots are logged in the output section of the test report if --buildUrl is passed. --buildUrl needs to be set to $BUILD_URL Jenkins environment variable
- the crash log for each failed test will be saved under CrashLogs/ folder under JUnit report path
- the last screenshots are saved for each test in a separate folder in $LAST_SCREENSHOTS_PATH path and in the order they were created in test
- the consecutive identical screenshots can be excluded, to save just the relevant screenshots
- the generated files can be easily added as artifacts in Jenkins for the tests job
- supports Xcode 9's parallel testing. Multiple test results are placed in numbered subdirectories and reports are differentiated by device name & iOS version

## Usage e.g:
xcodebuild -derivedDataPath $DERIVED_DATA_PATH test

cd Build/Products/Release/

ProcessTestSummaries --logsTestPath $DERIVED_DATA_PATH/Logs/Test --jUnitReportPath $REPORTS_PATH/unitTestResult.xml --screenshotsPath $LAST_SCREENSHOTS_PATH --screenshotsCount 10 --buildUrl $BUILD_URL --excludeIdenticalScreenshots

## IDE, source code language supported:
Xcode 9, Swift 3

## Please, give a star to this project if it helps you.

## Contact
[Profile](http://nacuteodor.wix.com/profile)

## Related projects:
https://github.com/nacuteodor/SearchInJenkinsLogs
