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
        let args = CommandLine.arguments
        let arguments = args.joined(separator: " ")
        var argsOptionValues = arguments.components(separatedBy: ArgumentOptionsParser.kArgsSeparator)
        argsOptionValues.remove(at: 0)
        var parsedOptions = [String: String]()
        for  argsOptionValue in  argsOptionValues {
            let rangeToRemove = argsOptionValue.range(of: " ")
            let optionName = argsOptionValue.substring(to: rangeToRemove?.lowerBound ?? argsOptionValue.endIndex)
            var optionValue = argsOptionValue
            optionValue.replaceSubrange(optionValue.startIndex..<(rangeToRemove?.upperBound ?? optionValue.endIndex), with: "")
            parsedOptions[optionName] = optionValue
        }
        return parsedOptions
    }

    func validateOptionIsNotEmpty(optionName: String, optionValue: String) {
        if optionValue.isEmpty {
            try! CustomErrorType.invalidArgument(error: "\(ArgumentOptionsParser.kArgsSeparator)\(optionName) option value is empty.").throwsError()
        }
    }

    func validateOptionExistsAndIsNotEmpty(optionName: String, optionValue: String?) {
        guard let optionValue = optionValue else {
            try! CustomErrorType.invalidArgument(error: "\(ArgumentOptionsParser.kArgsSeparator)\(optionName) option value was not found.").throwsError()
            return
        }
        validateOptionIsNotEmpty(optionName: optionName, optionValue: optionValue)
    }
}
