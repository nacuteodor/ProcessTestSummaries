//
//  main.swift
//  ProcessTestSummaries
//
//  Created by Teodor Nacu on 23/05/16.
//  Copyright © 2016 Teo. All rights reserved.
//

import Foundation

private func getInvalidXMLCharacterSet() -> NSCharacterSet {
    // First, create a character set containing all valid UTF8 characters.
    let xmlCharacterSet = NSMutableCharacterSet()
    xmlCharacterSet.addCharactersInRange(NSMakeRange(0x9, 1))
    xmlCharacterSet.addCharactersInRange(NSMakeRange(0xA, 1))
    xmlCharacterSet.addCharactersInRange(NSMakeRange(0xD, 1))
    xmlCharacterSet.addCharactersInRange(NSMakeRange(0x20, 0xD7FF - 0x20))
    xmlCharacterSet.addCharactersInRange(NSMakeRange(0xE000, 0xFFFD - 0xE000))
    xmlCharacterSet.addCharactersInRange(NSMakeRange(0x10000, 0x10FFFF - 0x10000))

    // Then create and retain an inverted set, which will thus contain all invalid XML characters.
    //    invalidXMLCharacterSet = xmlCharacterSet.invertedSet
    return xmlCharacterSet.invertedSet
}

// First create a character set containing all invalid XML characters.
// Create this once and leave it in memory so that we can reuse it rather
// than recreate it every time we need it.
private let invalidXMLCharacterSet = getInvalidXMLCharacterSet()

/// Override XCTFail method to avoid importing XCTest framework for JSON extension
func XCTFail(message: String) {
    try! CustomErrorType.InvalidState(error: message).throwsError()
}

func contentsOfDirectoryAtPath(path: String) -> [String]? {
    let fileManager = NSFileManager.defaultManager()
    if fileManager.fileExistsAtPath(path) {
        do {
            return try fileManager.contentsOfDirectoryAtPath(path)
        } catch {
            print("Unable to access path \(path)")
            return nil
        }
    }
    return [String]()
}

func createFolderOrEmptyIfExistsAtPath(path: String, emptyPath: Bool = true) -> Bool {
    var containerSetupSuccess = true
    let filenames = contentsOfDirectoryAtPath(path)
    if filenames == nil {
        containerSetupSuccess = false
    } else {
        let fileManager = NSFileManager.defaultManager()
        if !fileManager.fileExistsAtPath(path) {
            // Folder doesn't exist at the specified path, we need to construct the folder structure
            do {
                try fileManager.createDirectoryAtPath(path, withIntermediateDirectories: true, attributes: nil)
            } catch {
                print("Cannot create folder container at path: \(path)")
                containerSetupSuccess = false
            }
        } else {
            if emptyPath && filenames?.count > 0 {
                for filePath in filenames! {
                    do { // no op
                        let completePath = path.stringByAppendingString(filePath)
                        try fileManager.removeItemAtPath(completePath)
                    } catch {
                        containerSetupSuccess = false
                        print("Unable empty old content at path: \(path)")
                    }
                }
            }
        }
    }
    return containerSetupSuccess
}

func validXMLString(string: String) -> String {
    // Not all UTF8 characters are valid XML.
    // See:
    // http://www.w3.org/TR/2000/REC-xml-20001006#NT-Char
    // (Also see: http://cse-mjmcl.cse.bris.ac.uk/blog/2007/02/14/1171465494443.html )
    //
    // The ranges of unicode characters allowed, as specified above, are:
    // Char ::= #x9 | #xA | #xD | [#x20-#xD7FF] | [#xE000-#xFFFD] | [#x10000-#x10FFFF] /* any Unicode character, excluding the surrogate blocks, FFFE, and FFFF. */
    //
    // To ensure the string is valid for XML encoding, we therefore need to remove any characters that
    // do not fall within the above ranges.

    // Are there any invalid characters in this string?
    var range = string.rangeOfCharacterFromSet(invalidXMLCharacterSet)

    // If not, just return self unaltered.
    if range == nil || range?.count == 0 {
        return string
    }

    // Otherwise go through and remove any illegal XML characters from a copy of the string.
    var cleanedString = string

    while range != nil && range?.count > 0 {
        cleanedString.removeRange(range!)
        range = cleanedString.rangeOfCharacterFromSet(invalidXMLCharacterSet)
    }

    return cleanedString
}



private func findTestSummariesPlistFile(logsTestPath logsTestPath: String) -> String {
    let summariesPlistSuffix = "TestSummaries.plist"
    var summariesPlistFile = ""
    var logsTestFiles = [String]()
    let fileManager = NSFileManager.defaultManager()
    if fileManager.fileExistsAtPath(logsTestPath) {
        do {
            logsTestFiles = try fileManager.contentsOfDirectoryAtPath(logsTestPath)
        } catch let e {
            try! CustomErrorType.InvalidState(error: "Error when getting files from \(logsTestPath) path : \(e)").throwsError()
        }
    }
    for file in logsTestFiles {
        if file.hasSuffix(summariesPlistSuffix) {
            summariesPlistFile = logsTestPath + "/" + file
            break
        }
    }
    return summariesPlistFile
}

private func getTestSummariesPlistJson(logsTestPath logsTestPath: String) -> JSON {
    let summariesPlistFile = findTestSummariesPlistFile(logsTestPath: logsTestPath)

    let summariesPlistDict = (NSDictionary(contentsOfFile: summariesPlistFile) as? Dictionary<String, AnyObject>) ?? Dictionary<String, AnyObject>()
    return JSON(summariesPlistDict)
}

/// Save the last @screenshotsCount screenshots to @lastScreenshotsPath folder from @logsTestPath test logs for failed tests
/// if screenshotsCount is -1 then save all screenshots available
/// - parameter excludeIdenticalScreenshots: excludes the consecutive identical screenshots, to get the relevant screenshots
func saveLastScreenshots(testSummariesPlistJson testSummariesPlistJson: JSON, logsTestPath: String, lastScreenshotsPath: String, screenshotsCount: Int, excludeIdenticalScreenshots: Bool = false) {
    print("Save last \(screenshotsCount) screenshots from \(logsTestPath) logs test folder to \(lastScreenshotsPath) folder")
    if logsTestPath.isEmpty {
        try! CustomErrorType.InvalidArgument(error: "Tests logs path is empty.").throwsError()
    }
    if lastScreenshotsPath.isEmpty {
        try! CustomErrorType.InvalidArgument(error: "Last screenshots path is empty.").throwsError()
    }

    let fileManager = NSFileManager.defaultManager()
    let appScreenShotsPath = logsTestPath + "/Attachments/"
    let testJsonPath: [SubscriptType] = ["^", "TestableSummaries", ".", "Tests", ".", "Subtests", ".", "Subtests", ".", "Subtests", "."]
    let testStatusJsonPath: [SubscriptType] = testJsonPath + ["TestStatus"]
    let testIdentifierJsonPath: [SubscriptType] = ["TestIdentifier"]
    // extract the failed test nodes for finding the test screenshots
    let failedTests = testSummariesPlistJson.getParentValuesFor(relativePath: testStatusJsonPath, withValue: JSON("Failure"))
    for failedTestNode in failedTests {
        let testIdentifier = failedTestNode[testIdentifierJsonPath].stringValue
        let testLastScreenShotsPath = lastScreenshotsPath + "/\(testIdentifier.stringByReplacingOccurrencesOfString("/", withString: "_"))/"

        // extract the last screenshotsCount screenshots filenames of the test
        var screenshotNodes = failedTestNode.getParentValuesFor(relativePath: ["HasScreenshotData"], withValue: JSON(true))
        // if screenshotsCount param is -1 then save all screenshots
        let screenshotsCount = screenshotsCount == -1 ? screenshotNodes.count : screenshotsCount
        var screenshotsFiles = [String]()
        var prevScreenshotsFile = ""
        if screenshotsCount > 0 && screenshotNodes.count > 0 {
            prevScreenshotsFile = "Screenshot_" + screenshotNodes[screenshotNodes.count - 1]["UUID"].stringValue + ".png"
            screenshotsFiles.append(prevScreenshotsFile)
        }
        for index in (screenshotNodes.count - 2).stride(to: 0, by: -1) where screenshotsCount > 0 {
            let node = screenshotNodes[index]
            let screenshotsFile = "Screenshot_" + node["UUID"].stringValue + ".png"
            if excludeIdenticalScreenshots {
                if !fileManager.contentsEqualAtPath(appScreenShotsPath + screenshotsFile, andPath: appScreenShotsPath + prevScreenshotsFile) {
                    screenshotsFiles.append(screenshotsFile)
                }
            } else {
                screenshotsFiles.append(screenshotsFile)
            }
            if screenshotsFiles.count == screenshotsCount {
                break
            }
            prevScreenshotsFile = screenshotsFile
        }
        if screenshotsFiles.count > 0 {
            // copy and rename the screenshots to a specific folder for the current test
            createFolderOrEmptyIfExistsAtPath(testLastScreenShotsPath)
            screenshotsFiles = screenshotsFiles.reverse()
            for index in 0..<screenshotsFiles.count {
                let screenshotFile = appScreenShotsPath + screenshotsFiles[index]
                let newScreenshotFile = testLastScreenShotsPath + "\(index).png"
                do {
                    try fileManager.copyItemAtPath(screenshotFile, toPath: newScreenshotFile)
                } catch let e {
                    try! CustomErrorType.InvalidState(error: "Error when copying \(screenshotFile) file to \(newScreenshotFile) : \(e)").throwsError()
                }
            }
            print("Saved the last \(screenshotsCount) screenshots at path: \(testLastScreenShotsPath) ")
        }
    }
}

/// Generate JUnit report xml file from TestSummaries plist file from @logsTestPath logs test folder at path @jUnitRepPath
func generateJUnitReport(testSummariesPlistJson testSummariesPlistJson: JSON, logsTestPath: String, jUnitRepPath: String) {
    print("Generate JUnit report xml file from \(logsTestPath) logs test folder to \(jUnitRepPath) file")

    // parse the TestSummaries plist file and create the JUnit xml document
    let testSuitesNode = NSXMLElement(name: "testsuites")
    let jUnitXml = NSXMLDocument(rootElement: testSuitesNode)

    let testableSummariesJsonPath: [SubscriptType] = ["TestableSummaries"]
    let testSuitesJsonPath: [SubscriptType] = ["^", "Tests", ".", "Subtests", ".", "Subtests", "."]
    let subtestsJsonPath: [SubscriptType] = ["Subtests"]
    let targetNameJsonPath: [SubscriptType] = ["TargetName"]
    let testNameJsonPath: [SubscriptType] = ["TestName"]
    let testStatusJsonPath: [SubscriptType] = ["TestStatus"]
    let failureSummariesJsonPath: [SubscriptType] = ["FailureSummaries"]
    let activitySummariesJsonPath: [SubscriptType] = ["ActivitySummaries"]
    let titleJsonPath: [SubscriptType] = ["Title"]
    let messageJsonPath: [SubscriptType] = ["Message"]
    let startTimeIntervalJsonPath: [SubscriptType] = ["StartTimeInterval"]
    let finishTimeIntervalJsonPath: [SubscriptType] = ["FinishTimeInterval"]
    let fileNameJsonPath: [SubscriptType] = ["FileName"]
    let lineNumberJsonPath: [SubscriptType] = ["LineNumber"]

    let testableSummariesJsons = testSummariesPlistJson[testableSummariesJsonPath].arrayValue
    var totalTestsCount = 0
    var totalFailuresCount = 0
    for testableSummaryJson in testableSummariesJsons {
        let targetName = testableSummaryJson[targetNameJsonPath].stringValue
        let testSuitesJsons = testableSummaryJson.values(relativePath: testSuitesJsonPath)

        for testSuitesJson in testSuitesJsons {
            let testSuiteNode = NSXMLElement(name: "testsuite")

            let testSuiteName = targetName + "." + testSuitesJson[testNameJsonPath].stringValue
            let testCasesJsons = testSuitesJson[subtestsJsonPath].arrayValue
            var failuresCount = 0
            for testCaseJson in testCasesJsons {
                let testCaseNode = NSXMLElement(name: "testcase")

                let testCaseName = testCaseJson[testNameJsonPath].stringValue.stringByReplacingOccurrencesOfString("()", withString: "")
                let testCaseStatus =  testCaseJson[testStatusJsonPath].stringValue

                var time = "0"
                let activitySummariesJson = testCaseJson[activitySummariesJsonPath]
                if testCaseStatus != "Success" {
                    failuresCount += 1
                    var outputLogs = [String]()
                    var failureStackTrace = ""
                    var failureMessage = ""
                    let failureSummariesJson = testCaseJson[failureSummariesJsonPath]
                    if failureSummariesJson.arrayValue.count > 0 {
                        let firstFailureSummaryJson = failureSummariesJson[0]
                        failureMessage = validXMLString(firstFailureSummaryJson[messageJsonPath].stringValue)
                        var fileName = firstFailureSummaryJson[fileNameJsonPath].stringValue
                        let rangeToRemove = fileName.rangeOfString(targetName + "/")
                        fileName.replaceRange(fileName.startIndex..<(rangeToRemove?.startIndex ?? fileName.startIndex), with: "")
                        let lineNumber = firstFailureSummaryJson[lineNumberJsonPath].intValue
                        failureStackTrace = fileName + ":" + String(lineNumber)
                    }
                    outputLogs = JSON.values(activitySummariesJson.values(relativePath: titleJsonPath))

                    let failureNode = NSXMLElement(name: "failure", stringValue: failureStackTrace)
                    let messageAttr = NSXMLNode.attributeWithName("message", stringValue: failureMessage)  as! NSXMLNode
                    failureNode.attributes = [messageAttr]
                    let systemOutNode = NSXMLElement(name: "system-out", stringValue: validXMLString(outputLogs.joinWithSeparator("\n")))
                    testCaseNode.addChild(failureNode)
                    testCaseNode.addChild(systemOutNode)
                }
                if activitySummariesJson.arrayValue.count > 0 {
                    let startTime = Double(activitySummariesJson.arrayValue[0][startTimeIntervalJsonPath].stringValue) ?? 0.0
                    let lastActivitySummaryJson = activitySummariesJson.arrayValue[activitySummariesJson.count - 1]
                    var finishTimeIntervalJsons = lastActivitySummaryJson.values(relativePath: finishTimeIntervalJsonPath)
                    var finishTimeIntervalJson = finishTimeIntervalJsons.count > 0 ? finishTimeIntervalJsons[finishTimeIntervalJsons.count - 1] : JSON.nullJSON
                    if finishTimeIntervalJsons.count == 0 {
                         finishTimeIntervalJsons = lastActivitySummaryJson.values(relativePath: startTimeIntervalJsonPath)
                        finishTimeIntervalJson = finishTimeIntervalJsons.count > 0 ? finishTimeIntervalJsons[finishTimeIntervalJsons.count - 1] : JSON.nullJSON
                    }
                    let endTime = Double(finishTimeIntervalJson.stringValue) ?? 0.0
                    time = String(format: "%.3f", endTime - startTime)
                }

                let classnameAttr = NSXMLNode.attributeWithName("classname", stringValue: testSuiteName)  as! NSXMLNode
                let nameAttr = NSXMLNode.attributeWithName("name", stringValue: testCaseName) as! NSXMLNode
                let timeAttr = NSXMLNode.attributeWithName("time", stringValue: time) as! NSXMLNode
                testCaseNode.attributes = [classnameAttr, nameAttr, timeAttr]
                testSuiteNode.addChild(testCaseNode)
            }
            totalTestsCount += testCasesJsons.count
            totalFailuresCount += failuresCount

            let testSuiteNameAttr = NSXMLNode.attributeWithName("name", stringValue: testSuiteName)  as! NSXMLNode
            let testSuiteTestsAttr = NSXMLNode.attributeWithName("tests", stringValue:  String(testCasesJsons.count)) as! NSXMLNode
            let testSuiteFailuresAttr = NSXMLNode.attributeWithName("failures", stringValue: String(failuresCount)) as! NSXMLNode
            testSuiteNode.attributes = [testSuiteNameAttr, testSuiteTestsAttr, testSuiteFailuresAttr]
            testSuitesNode.addChild(testSuiteNode)
        }
    }

    let testSuitesTestsAttr = NSXMLNode.attributeWithName("tests", stringValue: String(totalTestsCount))  as! NSXMLNode
    let testSuitesFailuresAttr = NSXMLNode.attributeWithName("failures", stringValue: String(totalFailuresCount)) as! NSXMLNode
    testSuitesNode.attributes = [testSuitesTestsAttr, testSuitesFailuresAttr]

    // create the needed path for saving the report
    var pathTokens = jUnitRepPath.componentsSeparatedByString("/")
    let reportFileName = pathTokens.count > 0 ? pathTokens.removeLast() : ""
    if reportFileName.isEmpty {
        try! CustomErrorType.InvalidArgument(error: "\(jUnitRepPath) JUnit report path has an empty filename.").throwsError()
    }
    let jUnitRepParentDir = jUnitRepPath.stringByReplacingOccurrencesOfString("/" + reportFileName, withString: "")
    createFolderOrEmptyIfExistsAtPath(jUnitRepParentDir, emptyPath: false)

    // finally, save the xml report
    let xmlData = jUnitXml.XMLDataWithOptions(Int(NSXMLNodePrettyPrint))
    if !xmlData.writeToFile(jUnitRepPath, atomically: false) {
        try! CustomErrorType.InvalidArgument(error: "Writing xml data to file \(jUnitRepPath) failed!").throwsError()
    }
}


// ====== main ======

// ====== available options ======
let logsTestPathOption = "logsTestPath"
let jUnitReportPathOption = "jUnitReportPath"
let screenshotsPathOption = "screenshotsPath"
let screenshotsCountOption = "screenshotsCount"
let excludeIdenticalScreenshotsOption = "excludeIdenticalScreenshots"
let options: [String: String] = [
    logsTestPathOption: " logs test path",
    jUnitReportPathOption: "JUnit report Path",
    screenshotsPathOption: "last screenshots path",
    screenshotsCountOption: "last screenshots count",
    excludeIdenticalScreenshotsOption: "exclude the consecutive identical screenshots"
]
let argumentOptionsParser = ArgumentOptionsParser()
var parsedOptions = argumentOptionsParser.parseArgs()
print("Parsed options: \(parsedOptions)")
let logsTestPathOptionValue = parsedOptions[logsTestPathOption]
let jUnitReportPathOptionValue = parsedOptions[jUnitReportPathOption]
let screenshotsPathOptionValue = parsedOptions[screenshotsPathOption]
let screenshotsCountOptionValue = parsedOptions[screenshotsCountOption]
let excludeIdenticalScreenshotsOptionValue = parsedOptions[excludeIdenticalScreenshotsOption]

// ====== options validations ======
argumentOptionsParser.validateOptionExistsAndIsNotEmpty(optionName: logsTestPathOption, optionValue: logsTestPathOptionValue)

// at least jUnitReportPathOption or screenshotsPathOption should be passed as arguments
if jUnitReportPathOptionValue == nil && screenshotsPathOptionValue == nil {
    try! CustomErrorType.InvalidArgument(error: "\(ArgumentOptionsParser.kArgsSeparator)\(jUnitReportPathOption) or \(ArgumentOptionsParser.kArgsSeparator)\(screenshotsPathOption) option value doesn't exist.").throwsError()
}

var screenshotsCount = 5 // the default screenshots count value
if let screenshotsCountOptionValue = screenshotsCountOptionValue {
    argumentOptionsParser.validateOptionIsNotEmpty(optionName: screenshotsCountOption, optionValue: screenshotsCountOptionValue)
    screenshotsCount = Int(screenshotsCountOptionValue) ?? screenshotsCount
}

// exclude the consecutive identical screenshots if --excludeIdenticalScreenshots option is present
var excludeIdenticalScreenshots = excludeIdenticalScreenshotsOptionValue != nil

let logsTestPath = logsTestPathOptionValue!
let testSummariesPlistJson = getTestSummariesPlistJson(logsTestPath: logsTestPath)

// generate the report if --jUnitReportPath option is passed
if let jUnitReportPathOptionValue = jUnitReportPathOptionValue {
    argumentOptionsParser.validateOptionIsNotEmpty(optionName: jUnitReportPathOption, optionValue: jUnitReportPathOptionValue)

    generateJUnitReport(testSummariesPlistJson: testSummariesPlistJson, logsTestPath: logsTestPath, jUnitRepPath: jUnitReportPathOptionValue)
}

// save the last screenshots if --screenshotsPath option is passed
if let screenshotsPathOptionValue = screenshotsPathOptionValue {
    argumentOptionsParser.validateOptionIsNotEmpty(optionName: screenshotsPathOption, optionValue: screenshotsPathOptionValue)
    
    saveLastScreenshots(testSummariesPlistJson: testSummariesPlistJson, logsTestPath: logsTestPath, lastScreenshotsPath: screenshotsPathOptionValue, screenshotsCount: screenshotsCount, excludeIdenticalScreenshots: excludeIdenticalScreenshots)
}
