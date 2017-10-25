//
//  main.swift
//  ProcessTestSummaries
//
//  Created by Teodor Nacu on 23/05/16.
//  Copyright © 2016 Teo. All rights reserved.
//

import Foundation
// FIXME: comparison operators with optionals were removed from the Swift Standard Libary.
// Consider refactoring the code to use the non-optional operators.
fileprivate func < <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
  switch (lhs, rhs) {
  case let (l?, r?):
    return l < r
  case (nil, _?):
    return true
  default:
    return false
  }
}

// FIXME: comparison operators with optionals were removed from the Swift Standard Libary.
// Consider refactoring the code to use the non-optional operators.
fileprivate func > <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
  switch (lhs, rhs) {
  case let (l?, r?):
    return l > r
  default:
    return rhs < lhs
  }
}


private func getInvalidXMLCharacterSet() -> CharacterSet {
    // First, create a character set containing all valid UTF8 characters.
    let xmlCharacterSet = NSMutableCharacterSet()
    xmlCharacterSet.addCharacters(in: NSMakeRange(0x9, 1))
    xmlCharacterSet.addCharacters(in: NSMakeRange(0xA, 1))
    xmlCharacterSet.addCharacters(in: NSMakeRange(0xD, 1))
    xmlCharacterSet.addCharacters(in: NSMakeRange(0x20, 0xD7FF - 0x20))
    xmlCharacterSet.addCharacters(in: NSMakeRange(0xE000, 0xFFFD - 0xE000))
    xmlCharacterSet.addCharacters(in: NSMakeRange(0x10000, 0x10FFFF - 0x10000))

    // Then create and retain an inverted set, which will thus contain all invalid XML characters.
    //    invalidXMLCharacterSet = xmlCharacterSet.invertedSet
    return xmlCharacterSet.inverted
}

// First create a character set containing all invalid XML characters.
// Create this once and leave it in memory so that we can reuse it rather
// than recreate it every time we need it.
private let invalidXMLCharacterSet = getInvalidXMLCharacterSet()

/// Override XCTFail method to avoid importing XCTest framework for JSON extension
func XCTFail(_ message: String) {
    try! CustomErrorType.invalidState(error: message).throwsError()
}

func contentsOfDirectoryAtPath(_ path: String) -> [String]? {
    let fileManager = FileManager.default
    if fileManager.fileExists(atPath: path) {
        do {
            return try fileManager.contentsOfDirectory(atPath: path)
        } catch {
            print("Unable to access path \(path)")
            return nil
        }
    }
    return [String]()
}

func createFolderOrEmptyIfExistsAtPath(_ path: String, emptyPath: Bool = true) -> Bool {
    var containerSetupSuccess = true
    let filenames = contentsOfDirectoryAtPath(path)
    if filenames == nil {
        containerSetupSuccess = false
    } else {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: path) {
            // Folder doesn't exist at the specified path, we need to construct the folder structure
            do {
                try fileManager.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: nil)
            } catch {
                print("Cannot create folder container at path: \(path)")
                containerSetupSuccess = false
            }
        } else {
            if emptyPath && filenames?.count > 0 {
                for filePath in filenames! {
                    do { // no op
                        let completePath = path + filePath
                        try fileManager.removeItem(atPath: completePath)
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

func validXMLString(_ string: String) -> String {
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
    var range = string.rangeOfCharacter(from: invalidXMLCharacterSet)

    // If not, just return self unaltered.
    if range == nil || range!.isEmpty {
        return string
    }

    // Otherwise go through and remove any illegal XML characters from a copy of the string.
    var cleanedString = string

    while range != nil && range!.isEmpty == false {
        cleanedString.removeSubrange(range!)
        range = cleanedString.rangeOfCharacter(from: invalidXMLCharacterSet)
    }

    return cleanedString
}



private func findTestSummariesPlistFiles(logsTestPath: String) -> [String] {
    let summariesPlistSuffix = "TestSummaries.plist"
    var summariesPlistFiles = [String]()
    var logsTestFiles = [String]()
    let fileManager = FileManager.default
    if fileManager.fileExists(atPath: logsTestPath) {
        do {
            logsTestFiles = try fileManager.contentsOfDirectory(atPath: logsTestPath)
        } catch let e {
            try! CustomErrorType.invalidState(error: "Error when getting files from \(logsTestPath) path : \(e)").throwsError()
        }
    }
    for file in logsTestFiles {
        if file.hasSuffix(summariesPlistSuffix) {
            summariesPlistFiles.append(logsTestPath + "/" + file)
        }
    }
    return summariesPlistFiles
}

private func getTestSummariesPlistJsons(logsTestPath: String) -> [JSON] {
    var jsons = [JSON]()
    let summariesPlistFiles = findTestSummariesPlistFiles(logsTestPath: logsTestPath)

    summariesPlistFiles.forEach { summariesPlistFile in
        let summariesPlistDict = (NSDictionary(contentsOfFile: summariesPlistFile) as? Dictionary<String, AnyObject>) ?? Dictionary<String, AnyObject>()
        jsons.append(JSON(summariesPlistDict))
    }

    return jsons
}

/**
 * Encodes "\n" characters between <failure...</failure> with "&#10;", so those won't be replaced with space char when parsing the xml document
 *
 * @param xml the xml as String, we need to transform
 * @return a new xml
 */
private func encodeNewLineCharInFailureElement(xml: String, failureTag: String, failureEndTag: String) -> String {
    var xml = xml
    var newXml = ""
    var replace = false
    let maxNewLinesToReplace = 100 // this is limited to make sure the tool doesn't run out of memory, for e.g. for a large json
    var replacedNewLinesCount = 0
    while (!xml.isEmpty) {
        var newLinePosition = xml.range(of: failureTag)
        if (newLinePosition == nil) {
            newXml.append(xml);
            break;
        }
        var newLine = xml.substring(to: newLinePosition!.lowerBound)
        newXml.append(newLine)
        xml = xml.substring(from: newLinePosition!.lowerBound)
        var finishedReplace = false
        while !finishedReplace {
            newLinePosition = xml.range(of: "\n")
            if (newLinePosition == nil) {
                newXml.append(xml);
                return newXml
            }
            newLine = xml.substring(to: newLinePosition!.lowerBound)
            if (newLine.range(of: failureEndTag) == nil && replacedNewLinesCount < maxNewLinesToReplace) {
                if (newLine.range(of: failureTag) != nil) {
                    newLine.append("&#10;")
                    replace = true
                    replacedNewLinesCount = 1
                } else if (replace) {
                    newLine.append("&#10;")
                    replacedNewLinesCount += 1
                } else {
                    newLine.append("\n");
                }
            } else {
                replace = false;
                replacedNewLinesCount = 0;
                newLine.append("\n");
                // go to the next failure if we replaced the maximum new lines
                finishedReplace = true;
            }
            newXml.append(newLine);
            xml = xml.substring(from: xml.characters.index(after: newLinePosition!.lowerBound));
        }
    }
    return newXml;
}

private func encodeNewLineCharInFailureElements(xml: String) -> String {
    var newXml = encodeNewLineCharInFailureElement(xml: xml, failureTag: "<failure message=", failureEndTag: "</failure>");
    newXml = encodeNewLineCharInFailureElement(xml: newXml, failureTag: "<error message=", failureEndTag: "</error>");
    return newXml;
}

/// Save the last @screenshotsCount screenshots to @lastScreenshotsPath folder from @logsTestPath test logs for failed tests
/// if screenshotsCount is -1 then save all screenshots available
/// - parameter excludeIdenticalScreenshots: excludes the consecutive identical screenshots, to get the relevant screenshots
func saveLastScreenshots(testSummariesPlistJson: JSON, logsTestPath: String, lastScreenshotsPath: String, screenshotsCount: Int, excludeIdenticalScreenshots: Bool = false) {
    print("Save last \(screenshotsCount) screenshots from \(logsTestPath) logs test folder to \(lastScreenshotsPath) folder")
    if logsTestPath.isEmpty {
        try! CustomErrorType.invalidArgument(error: "Tests logs path is empty.").throwsError()
    }
    if lastScreenshotsPath.isEmpty {
        try! CustomErrorType.invalidArgument(error: "Last screenshots path is empty.").throwsError()
    }

    let lastScreenshotsPath: String = {
        if lastScreenshotsPath.characters.last == "/" {
            return lastScreenshotsPath.substring(to: lastScreenshotsPath.index(before: lastScreenshotsPath.endIndex))
        }
        else {
            return lastScreenshotsPath
        }
    }()

    let fileManager = FileManager.default
    let appScreenShotsPath = logsTestPath + "/Attachments/"
    let testJsonPath: [JSONSubscriptType] = ["^", "TestableSummaries", ".", "Tests", ".", "Subtests", ".", "Subtests", ".", "Subtests", "."]
    let testStatusJsonPath: [JSONSubscriptType] = testJsonPath + ["TestStatus"]
    let testIdentifierJsonPath: [JSONSubscriptType] = ["TestIdentifier"]
    // extract the failed test nodes for finding the test screenshots
    let failedTests = testSummariesPlistJson.getParentValuesFor(relativePath: testStatusJsonPath, withValue: JSON("Failure"))
    for failedTestNode in failedTests {
        let testIdentifier = failedTestNode[testIdentifierJsonPath].stringValue
        let testLastScreenShotsPath = lastScreenshotsPath + "/\(testIdentifier.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "()", with: ""))/"

        // extract the last screenshotsCount screenshots filenames of the test
        let lastPathsLimit = screenshotsCount == -1 ? Int.max : 4 * screenshotsCount
        var screenshotNodes = failedTestNode.getParentValuesFor(relativePath: ["HasScreenshotData"], lastPathsLimit: lastPathsLimit, withValue: JSON(true))
        if screenshotsCount != -1 {
            screenshotNodes = screenshotNodes.reversed()
        }
        // if screenshotsCount param is -1 then save all screenshots
        let screenshotsCount = screenshotsCount == -1 ? screenshotNodes.count : screenshotsCount
        var screenshotsFiles = [String]()
        var prevScreenshotsFile = ""
        if screenshotsCount > 0 && screenshotNodes.count > 0 {
            prevScreenshotsFile = "Screenshot_" + screenshotNodes[screenshotNodes.count - 1]["UUID"].stringValue + ".jpg"
            screenshotsFiles.append(prevScreenshotsFile)
        }
        for index in stride(from: (screenshotNodes.count - 2), to: -1, by: -1) where screenshotsCount > 0 {
            let node = screenshotNodes[index]
            let screenshotsFile = "Screenshot_" + node["UUID"].stringValue + ".jpg"
            if excludeIdenticalScreenshots {
                if !fileManager.contentsEqual(atPath: appScreenShotsPath + screenshotsFile, andPath: appScreenShotsPath + prevScreenshotsFile) {
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
            screenshotsFiles = screenshotsFiles.reversed()
            for index in 0..<screenshotsFiles.count {
                let screenshotFile = appScreenShotsPath + screenshotsFiles[index]
                let newScreenshotFile = testLastScreenShotsPath + "\(index).jpg"
                do {
                    try fileManager.copyItem(atPath: screenshotFile, toPath: newScreenshotFile)
                } catch let e {
                    try! CustomErrorType.invalidState(error: "Error when copying \(screenshotFile) file to \(newScreenshotFile) : \(e)").throwsError()
                }
            }
            print("Saved the last \(screenshotsCount) screenshots at path: \(testLastScreenShotsPath) ")
        }
    }
}

/// Get Jenkins build relative last screenshots path
func getJenkinsLastScreenshotsPath(_ lastScreenshotsPath: String, junitPath: String) -> String {
    let commonPath = lastScreenshotsPath.commonPrefix(with: junitPath, options: NSString.CompareOptions.literal)

    return lastScreenshotsPath.replacingOccurrences(of: commonPath, with: "")
}

/// Generate JUnit report xml file from TestSummaries plist file from @logsTestPath logs test folder at path @jUnitRepPath
/// - parameter lastScreenshotsPath: used to compute the Jenkins relative path to build artifacts
/// - parameter buildUrl: Jenkins build url $BUILD_URL environment variable
/// - parameter workspacePath: the workspace path of the repo, to be removed from stacktrace if it is found, to remain just the relative path file
func generateJUnitReport(testSummariesPlistJson: JSON, logsTestPath: String, jUnitRepPath: String, noCrashLogs: Bool, lastScreenshotsPath: String? = nil, screenshotsCount: Int, buildUrl: String?, workspacePath: String) {
    print("Generate JUnit report xml file from \(logsTestPath) logs test folder to \(jUnitRepPath) file")

    // create the needed path for saving the report
    var pathTokens = jUnitRepPath.components(separatedBy: "/")
    let reportFileName = pathTokens.count > 0 ? pathTokens.removeLast() : ""
    if reportFileName.isEmpty {
        try! CustomErrorType.invalidArgument(error: "\(jUnitRepPath) JUnit report path has an empty filename.").throwsError()
    }
    let fileManager = FileManager.default
    let jUnitRepParentDir = jUnitRepPath.replacingOccurrences(of: "/" + reportFileName, with: "")
    createFolderOrEmptyIfExistsAtPath(jUnitRepParentDir, emptyPath: false)
    var testLastScreenShotsLink: String = ""
    if let lastScreenshotsPath = lastScreenshotsPath, let buildUrl = buildUrl {
        let screenshotsPath = getJenkinsLastScreenshotsPath(lastScreenshotsPath, junitPath: jUnitRepParentDir)
        testLastScreenShotsLink = "\(buildUrl)artifact/\(screenshotsPath)/"
    }
    let testsCrashLogsPath = jUnitRepParentDir + "/CrashLogs/"
    let crashLogsPath = logsTestPath + "/Attachments/"

    // parse the TestSummaries plist file and create the JUnit xml document
    let testSuitesNode = XMLElement(name: "testsuites")
    let jUnitXml = XMLDocument(rootElement: testSuitesNode)

    let testableSummariesJsonPath: [JSONSubscriptType] = ["TestableSummaries"]
    let testSuitesJsonPath: [JSONSubscriptType] = ["^", "Tests", ".", "Subtests", ".", "Subtests", "."]
    let subtestsJsonPath: [JSONSubscriptType] = ["Subtests"]
    let targetNameJsonPath: [JSONSubscriptType] = ["TargetName"]
    let testNameJsonPath: [JSONSubscriptType] = ["TestName"]
    let testIdentifierJsonPath: [JSONSubscriptType] = ["TestIdentifier"]
    let testStatusJsonPath: [JSONSubscriptType] = ["TestStatus"]
    let failureSummariesJsonPath: [JSONSubscriptType] = ["FailureSummaries"]
    let activitySummariesJsonPath: [JSONSubscriptType] = ["ActivitySummaries"]
    let titleJsonPath: [JSONSubscriptType] = ["Title"]
    let messageJsonPath: [JSONSubscriptType] = ["Message"]
    let startTimeIntervalJsonPath: [JSONSubscriptType] = ["StartTimeInterval"]
    let finishTimeIntervalJsonPath: [JSONSubscriptType] = ["FinishTimeInterval"]
    let fileNameJsonPath: [JSONSubscriptType] = ["FileName"]
    let lineNumberJsonPath: [JSONSubscriptType] = ["LineNumber"]
    let hasDiagnosticReportDataJsonPath: [JSONSubscriptType] = ["HasDiagnosticReportData"]
    let diagnosticReportFileNameJsonPath: [JSONSubscriptType] = ["DiagnosticReportFileName"]
    let uuidJsonPath: [JSONSubscriptType] = ["UUID"]
    let deviceNamePath: [JSONSubscriptType] = ["RunDestination", "TargetDevice", "ModelName"]
    let deviceOSPath: [JSONSubscriptType] = ["RunDestination", "TargetDevice", "OperatingSystemVersionWithBuildNumber"]

    let testableSummariesJsons = testSummariesPlistJson[testableSummariesJsonPath].arrayValue
    let testDeviceName = testSummariesPlistJson[deviceNamePath].stringValue
    let testDeviceOSVersion = testSummariesPlistJson[deviceOSPath].stringValue
    let testDeviceDescription = testDeviceName + " " + testDeviceOSVersion

    var totalTestsCount = 0
    var totalFailuresCount = 0
    for testableSummaryJson in testableSummariesJsons {
        // With Xcode 9, the top-level "TestName" in the testable summary is the target name
        let targetName: String = {
            let targetName = testableSummaryJson[targetNameJsonPath].stringValue
            return !targetName.isEmpty ? testDeviceDescription + " " + targetName : testDeviceDescription + " " + testableSummaryJson[testNameJsonPath].stringValue
        }()

        let testSuitesJsons = testableSummaryJson.values(relativePath: testSuitesJsonPath)

        for testSuitesJson in testSuitesJsons {
            let testSuiteNode = XMLElement(name: "testsuite")

            let testSuiteName = targetName + "." + testSuitesJson[testNameJsonPath].stringValue
            let testCasesJsons = testSuitesJson[subtestsJsonPath].arrayValue
            var failuresCount = 0
            for testCaseJson in testCasesJsons {
                let testCaseNode = XMLElement(name: "testcase")
                let testIdentifier = testCaseJson[testIdentifierJsonPath].stringValue
                let testCaseName = testCaseJson[testNameJsonPath].stringValue.replacingOccurrences(of: "()", with: "")
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
                        let rangeToRemove = fileName.range(of: targetName + "/")
                        fileName.replaceSubrange(fileName.startIndex..<(rangeToRemove?.lowerBound ?? fileName.startIndex), with: "")
                        let lineNumber = firstFailureSummaryJson[lineNumberJsonPath].intValue
                        fileName = fileName.replacingOccurrences(of: workspacePath, with: "")
                        failureStackTrace = fileName + ":" + String(lineNumber)
                    }
                    outputLogs = JSON.values(activitySummariesJson.values(relativePath: titleJsonPath, lastPathsLimit: Int.max - 1, maxArrayCount: 400))
                    outputLogs = outputLogs.reversed()
                    let crashSummaries: [JSON] = noCrashLogs ? [JSON]() : activitySummariesJson.getParentValuesFor(relativePath: hasDiagnosticReportDataJsonPath, lastPathsLimit: 1, maxArrayCount: 100, withValue: JSON(true))
                    // if we have a crash log for the current test, save it
                    if crashSummaries.count > 0 {
                        let crashSummary = crashSummaries[0]
                        let crashFilename = crashSummary[diagnosticReportFileNameJsonPath].stringValue
                        let testIdentifier = testCaseJson[testIdentifierJsonPath].stringValue
                        let savedCrashLogName = testIdentifier.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "()", with: "") + ".crash.txt"
                        let newTestCrashLogFile = testsCrashLogsPath + savedCrashLogName
                        createFolderOrEmptyIfExistsAtPath(testsCrashLogsPath, emptyPath: false)
                        let crashLogsFile = crashLogsPath + crashFilename
                        if fileManager.fileExists(atPath: newTestCrashLogFile) {
                            do {
                                try fileManager.removeItem(atPath: newTestCrashLogFile)
                            } catch let e {
                                try! CustomErrorType.invalidState(error: "Error when removing \(newTestCrashLogFile) file : \(e)").throwsError()
                            }
                        }
                        do {
                            try fileManager.copyItem(atPath: crashLogsFile, toPath: newTestCrashLogFile)
                        } catch let e {
                            try! CustomErrorType.invalidState(error: "Error when copying \(crashLogsFile) file to \(newTestCrashLogFile) : \(e)").throwsError()
                        }
                        print("Saved the crash to path: \(newTestCrashLogFile)")
                    }

                    let failureNode = XMLElement(name: "failure", stringValue: failureStackTrace)
                    let messageAttr = XMLNode.attribute(withName: "message", stringValue: failureMessage)  as! XMLNode
                    failureNode.attributes = [messageAttr]
                    var testLastScreenShotsLinks: String = ""
                    if !testLastScreenShotsLink.isEmpty {
                        let jenkinsScreenshotsLink = "\(testLastScreenShotsLink)\(testIdentifier.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "()", with: ""))/"
                        testLastScreenShotsLinks = "Last Screenshots: \(jenkinsScreenshotsLink)\n \n"
                        for i in (0..<screenshotsCount).reversed()  {
                            testLastScreenShotsLinks.append(jenkinsScreenshotsLink + "\(i).jpg\n")
                        }
                    }
                    let systemOutNode = XMLElement(name: "system-out", stringValue: testLastScreenShotsLinks + validXMLString(outputLogs.joined(separator: "\n")))
                    testCaseNode.addChild(failureNode)
                    testCaseNode.addChild(systemOutNode)
                }
                if activitySummariesJson.arrayValue.count > 0 {
                    let startTime = Double(activitySummariesJson.arrayValue[0][startTimeIntervalJsonPath].stringValue) ?? 0.0
                    let lastActivitySummaryJson = activitySummariesJson.arrayValue[activitySummariesJson.count - 1]
                    var finishTimeIntervalJsons = lastActivitySummaryJson.values(relativePath: finishTimeIntervalJsonPath)
                    var finishTimeIntervalJson = finishTimeIntervalJsons.count > 0 ? finishTimeIntervalJsons[finishTimeIntervalJsons.count - 1] : JSON.null
                    if finishTimeIntervalJsons.count == 0 {
                         finishTimeIntervalJsons = lastActivitySummaryJson.values(relativePath: startTimeIntervalJsonPath)
                        finishTimeIntervalJson = finishTimeIntervalJsons.count > 0 ? finishTimeIntervalJsons[finishTimeIntervalJsons.count - 1] : JSON.null
                    }
                    let endTime = Double(finishTimeIntervalJson.stringValue) ?? 0.0
                    time = String(format: "%.3f", endTime - startTime)
                }

                let classnameAttr = XMLNode.attribute(withName: "classname", stringValue: testSuiteName)  as! XMLNode
                let nameAttr = XMLNode.attribute(withName: "name", stringValue: testCaseName) as! XMLNode
                let timeAttr = XMLNode.attribute(withName: "time", stringValue: time) as! XMLNode
                testCaseNode.attributes = [classnameAttr, nameAttr, timeAttr]
                testSuiteNode.addChild(testCaseNode)
            }
            totalTestsCount += testCasesJsons.count
            totalFailuresCount += failuresCount

            let testSuiteNameAttr = XMLNode.attribute(withName: "name", stringValue: testSuiteName)  as! XMLNode
            let testSuiteTestsAttr = XMLNode.attribute(withName: "tests", stringValue:  String(testCasesJsons.count)) as! XMLNode
            let testSuiteFailuresAttr = XMLNode.attribute(withName: "failures", stringValue: String(failuresCount)) as! XMLNode
            testSuiteNode.attributes = [testSuiteNameAttr, testSuiteTestsAttr, testSuiteFailuresAttr]
            testSuitesNode.addChild(testSuiteNode)
        }
    }

    let testSuitesTestsAttr = XMLNode.attribute(withName: "tests", stringValue: String(totalTestsCount))  as! XMLNode
    let testSuitesFailuresAttr = XMLNode.attribute(withName: "failures", stringValue: String(totalFailuresCount)) as! XMLNode
    let testSuitesNameAttr = XMLNode.attribute(withName: "name", stringValue: testDeviceDescription) as! XMLNode
    testSuitesNode.attributes = [testSuitesTestsAttr, testSuitesFailuresAttr, testSuitesNameAttr]

    // finally, save the xml report
    let xmlData = jUnitXml.xmlData(withOptions: Int(XMLNode.Options.nodePrettyPrint.rawValue))
    let xmlString = encodeNewLineCharInFailureElements(xml: String.init(data: xmlData, encoding: String.Encoding.utf8) ?? "")
    if (try? xmlString.write(toFile: jUnitRepPath, atomically: true, encoding: String.Encoding.utf8)) == nil {
        try! CustomErrorType.invalidArgument(error: "Writing xml data to file \(jUnitRepPath) failed!").throwsError()
    }
}

/// Appends a subdirectory to the given string representing a folder filepath. If the provided
/// subdirectory is an empty string, this simply returns the original path.
/// - Parameter path: String representing target directory
/// - Parameter subDirectory: String representing the subdirectory you wish to append to path
/// - Returns: The new subdirectory path under the original path
func appendSubdirectoryToPath(_ path: String?, subDirectory: String) -> String? {
    guard let path = path else {
        return nil
    }

    if subDirectory.isEmpty {
        return path
    }
    let subDirectory: String = {
        return subDirectory.last == "/" ? subDirectory : subDirectory + "/"
    }()

    return path.last == "/" ? path + subDirectory : path + "/" + subDirectory
}

/// Gets the folder from a path to a file. For example, supplying "/Users/name/file.txt" will
/// return "/Users/name/"
/// - Parameter path: String representing a path to a file
/// - Returns: String representing the containing folder for the file
func getFolderPathFromFilePath(_ path: String) -> String {
    return path.replacingOccurrences(of: URL(fileURLWithPath: path).lastPathComponent, with: "")
}


// ====== main ======

// ====== available options ======
let logsTestPathOption = "logsTestPath"
let jUnitReportPathOption = "jUnitReportPath"
let noCrashLogsOption = "noCrashLogs"
let screenshotsPathOption = "screenshotsPath"
let screenshotsCountOption = "screenshotsCount"
let excludeIdenticalScreenshotsOption = "excludeIdenticalScreenshots"
let buildUrlOption = "buildUrl"
let workspacePath = "workspacePath"
let options: [String: String] = [
    logsTestPathOption: " logs test path",
    jUnitReportPathOption: "JUnit report Path",
    noCrashLogsOption: "Don't save the crash logs",
    screenshotsPathOption: "last screenshots path",
    screenshotsCountOption: "last screenshots count",
    excludeIdenticalScreenshotsOption: "exclude the consecutive identical screenshots",
    buildUrlOption: "Jenkins BUILD_URL variable",
    workspacePath: "The workspace path of the repo"
]
let argumentOptionsParser = ArgumentOptionsParser()
var parsedOptions = argumentOptionsParser.parseArgs()
print("Parsed options: \(parsedOptions)")
let logsTestPathOptionValue = parsedOptions[logsTestPathOption]
let jUnitReportPathOptionValue = parsedOptions[jUnitReportPathOption]
let noCrashLogsOptionValue = parsedOptions[noCrashLogsOption]
let screenshotsPathOptionValue = parsedOptions[screenshotsPathOption]
let screenshotsCountOptionValue = parsedOptions[screenshotsCountOption]
let excludeIdenticalScreenshotsOptionValue = parsedOptions[excludeIdenticalScreenshotsOption]
let buildUrlOptionValue = parsedOptions[buildUrlOption]
let workspacePathOptionValue = parsedOptions[workspacePath]

// ====== options validations ======
argumentOptionsParser.validateOptionExistsAndIsNotEmpty(optionName: logsTestPathOption, optionValue: logsTestPathOptionValue)

// at least jUnitReportPathOption or screenshotsPathOption should be passed as arguments
if jUnitReportPathOptionValue == nil && screenshotsPathOptionValue == nil {
    try! CustomErrorType.invalidArgument(error: "\(ArgumentOptionsParser.kArgsSeparator)\(jUnitReportPathOption) or \(ArgumentOptionsParser.kArgsSeparator)\(screenshotsPathOption) option value doesn't exist.").throwsError()
}

// don't save the crash logs if --noCrashLogs option is present
var noCrashLogs = noCrashLogsOptionValue != nil

var screenshotsCount = 5 // the default screenshots count value
if let screenshotsCountOptionValue = screenshotsCountOptionValue {
    argumentOptionsParser.validateOptionIsNotEmpty(optionName: screenshotsCountOption, optionValue: screenshotsCountOptionValue)
    screenshotsCount = Int(screenshotsCountOptionValue) ?? screenshotsCount
}

// exclude the consecutive identical screenshots if --excludeIdenticalScreenshots option is present
var excludeIdenticalScreenshots = excludeIdenticalScreenshotsOptionValue != nil

let logsTestPath = logsTestPathOptionValue!
let testSummariesPlistJsons = getTestSummariesPlistJsons(logsTestPath: logsTestPath)

// save the last screenshots if --screenshotsPath option is passed
if let screenshotsPathOptionValue = screenshotsPathOptionValue {
    argumentOptionsParser.validateOptionIsNotEmpty(optionName: screenshotsPathOption, optionValue: screenshotsPathOptionValue)

    var fileCount = 1
    var subDirectory = testSummariesPlistJsons.count > 1 ? "\(fileCount)" : ""

    testSummariesPlistJsons.forEach { testSummariesPlistJson in
    saveLastScreenshots(testSummariesPlistJson: testSummariesPlistJson, logsTestPath: logsTestPath, lastScreenshotsPath: appendSubdirectoryToPath(screenshotsPathOptionValue, subDirectory: subDirectory)!, screenshotsCount: screenshotsCount, excludeIdenticalScreenshots: excludeIdenticalScreenshots)
        fileCount += 1
        subDirectory = "\(fileCount)"
    }

}

// generate the report if --jUnitReportPath option is passed
if let jUnitReportPathOptionValue = jUnitReportPathOptionValue {
    argumentOptionsParser.validateOptionIsNotEmpty(optionName: jUnitReportPathOption, optionValue: jUnitReportPathOptionValue)

    let path = getFolderPathFromFilePath(jUnitReportPathOptionValue)
    let fileName = URL(fileURLWithPath: jUnitReportPathOptionValue).lastPathComponent

    var fileCount = 1
    var subDirectory = testSummariesPlistJsons.count > 1 ? "\(fileCount)" : ""

    testSummariesPlistJsons.forEach { testSummariesPlistJson in
        generateJUnitReport(testSummariesPlistJson: testSummariesPlistJson, logsTestPath: logsTestPath, jUnitRepPath: appendSubdirectoryToPath(path, subDirectory: subDirectory)! + fileName, noCrashLogs: noCrashLogs, lastScreenshotsPath: appendSubdirectoryToPath(screenshotsPathOptionValue, subDirectory: subDirectory), screenshotsCount: screenshotsCount, buildUrl: buildUrlOptionValue, workspacePath: workspacePathOptionValue ?? "")
        fileCount += 1
        subDirectory = "\(fileCount)"
    }

}
