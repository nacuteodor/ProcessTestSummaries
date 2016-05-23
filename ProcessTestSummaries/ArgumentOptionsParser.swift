//
//  ArgumentOptionsParser.swift
//  ProcessTestSummaries
//
//  Created by Teodor Nacu on 23/05/16.
//  Copyright © 2016 Teo. All rights reserved.
//

import Foundation

/// Used to parse command line arguments with options starting with " --" prefix
struct ArgumentOptionsParser {
    static let kArgsSeparator = " --"

    // parse the arguments and return a dictionary of options values
    func parseArgs() -> [String: String] {
        let args = Process.arguments
        let arguments = args.joinWithSeparator(" ")
        var argsOptionValues = arguments.componentsSeparatedByString(ArgumentOptionsParser.kArgsSeparator)
        argsOptionValues.removeAtIndex(0)
        var parsedOptions = [String: String]()
        for  argsOptionValue in  argsOptionValues {
            let rangeToRemove = argsOptionValue.rangeOfString(" ")
            let optionName = argsOptionValue.substringToIndex(rangeToRemove?.startIndex ?? argsOptionValue.endIndex)
            var optionValue = argsOptionValue
            optionValue.replaceRange(optionValue.startIndex..<(rangeToRemove?.endIndex ?? optionValue.endIndex), with: "")
            parsedOptions[optionName] = optionValue
        }
        return parsedOptions
    }

    func validateOptionIsNotEmpty(optionName optionName: String, optionValue: String) {
        if optionValue.isEmpty {
            try! CustomErrorType.InvalidArgument(error: "\(ArgumentOptionsParser.kArgsSeparator)\(optionName) option value is empty.").throwsError()
        }
    }

    func validateOptionExistsAndIsNotEmpty(optionName optionName: String, optionValue: String?) {
        guard let optionValue = optionValue else {
            try! CustomErrorType.InvalidArgument(error: "\(ArgumentOptionsParser.kArgsSeparator)\(optionName) option value was not found.").throwsError()
            return
        }
        validateOptionIsNotEmpty(optionName: optionName, optionValue: optionValue)
    }
}