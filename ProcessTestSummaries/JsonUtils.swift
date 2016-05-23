//
//  JsonUtils.swift
//  ProcessTestSummaries
//
//  Created by Teodor Nacu on 23/05/16.
//  Copyright © 2016 Teo. All rights reserved.
//

import Foundation

extension JSON {

    static let kChildrenWildcard = "."
    static let kDescendantsWildcard = "*"
    static let kStarterWildcard = "^"

    /// Creates a JSON using a json string.
    /// E.g of json string: {"field1":"value1","field2":"value2","field3":{"field4:value4"}}
    /// - parameter string:  a json string
    public init(string: String) {
        if let dataFromString = string.dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: true) {
            self.init(data: dataFromString)
        } else {
            self.init(NSNull())
        }
    }

    /// - returns: true if @absolutePath absolute path matches the @relativePath relative path
    /// The relative match may contain wildcards like "*" for matching descendants of a json node, or "." for matching the children of a json node
    private static func matchesRelativePath(relativePath: [SubscriptType], absolutePath: [SubscriptType]) -> Bool {
        let starterSequence: [SubscriptType] = [kStarterWildcard]
        var relativePath = relativePath
        let fromStart = relativePath.startsWith(starterSequence) { (element, starter) -> Bool in
            return element == starter
        }
        if fromStart {
            relativePath.removeFirst()
        }
        if relativePath.count == 0 {
            return true
        }
        if fromStart {
            relativePath.removeFirst()
        }
        if absolutePath.count < relativePath.count {
            return false
        }
        var currentMatchedFieldIndex = 0
        var currentFieldFromRelativePath: SubscriptType = ""
        var matches = false
        for var fieldIndex in 0..<absolutePath.count {
            let field = absolutePath[fieldIndex]
            if currentMatchedFieldIndex < relativePath.count {
                currentFieldFromRelativePath = relativePath[currentMatchedFieldIndex]
                if field != currentFieldFromRelativePath && currentFieldFromRelativePath != kChildrenWildcard {
                    if currentFieldFromRelativePath != kDescendantsWildcard {
                        if currentMatchedFieldIndex < 1 || relativePath[currentMatchedFieldIndex - 1] != kDescendantsWildcard {
                            fieldIndex -= currentMatchedFieldIndex
                            currentMatchedFieldIndex = 0
                        }
                    } else {
                        currentMatchedFieldIndex += 1
                    }
                } else {
                    currentMatchedFieldIndex += 1
                }
            } else {
                if  currentMatchedFieldIndex >= 2 && relativePath[currentMatchedFieldIndex - 2] != kDescendantsWildcard {
                    fieldIndex -= currentMatchedFieldIndex
                    currentMatchedFieldIndex = 0
                }
            }

            if fromStart && fieldIndex == 0  && currentMatchedFieldIndex == 0 && currentFieldFromRelativePath != "*" {
                matches = false
                break
            }
            if  currentMatchedFieldIndex == relativePath.count {
                if fieldIndex == absolutePath.count - 1 && (field == currentFieldFromRelativePath || currentFieldFromRelativePath == kChildrenWildcard) {
                    matches = true
                    break
                } else if currentMatchedFieldIndex >= relativePath.count - 1 && currentFieldFromRelativePath == kDescendantsWildcard {
                    matches = true
                    break
                }
            }
        }
        return matches
    }

    /// - parameter json: The json where to find the @relativePath
    /// - parameter relativePath: The target json's relative path.
    /// Wildcard chars for children and descendants are supported in the json path: "." for children values of a json node, "*".
    /// Also, '^' can be used as the prefix the relative path to match the absolute path from beginning (beginning of the line).
    /// For e.g.: let jsonPath: [SubscriptType] = ["field1", ".", "*", "field2"]
    /// - parameter currentPath: The absolute json path for getting to @json value
    /// - returns: Returns the absolute paths matching the relative path @relativePath
    static private func paths(json: JSON, _ relativePath: [SubscriptType], _ currentPath: [SubscriptType]) -> [[SubscriptType]] {
        var absolutePaths: [[SubscriptType]] = [[SubscriptType]]()
        if json == JSON.nullJSON {
            return absolutePaths
        }
        if matchesRelativePath(relativePath, absolutePath: currentPath) {
            absolutePaths.append(currentPath)
        }
        switch json.type {
        case .Dictionary:
            for (key, value) in json.dictionaryValue {
                var newCurrentPath = currentPath
                newCurrentPath.append(key)
                absolutePaths += paths(value, relativePath, newCurrentPath)
            }
        case .Array:
            for index in 0 ..< json.arrayValue.count {
                let value = json.arrayValue[index]
                var newCurrentPath = currentPath
                newCurrentPath.append(index)
                absolutePaths += paths(value, relativePath, newCurrentPath)
            }
        default:
            break
        }
        return absolutePaths
    }

    /// - parameter relativePath: The target json's relative path
    /// - returns: Returns the absolute paths matching the relative path @relativePath in current json
    public func paths(relativePath relativePath: [SubscriptType]) -> [[SubscriptType]] {
        let paths: [[SubscriptType]] = JSON.paths(self, relativePath, [SubscriptType]())
        return paths
    }

    /// Get the json values found using the absolute paths @paths
    /// - parameter paths: an array with absolute json paths
    public func values(paths paths: [[SubscriptType]]) -> [JSON] {
        var values = [JSON]()
        for path in paths {
            values.append(self[path])
        }
        return values
    }

    /// Get the json values found using the relative path @relativePath
    /// - parameter relativePath: The target json's relative path
    public func values(relativePath relativePath: [SubscriptType]) -> [JSON] {
        let absolutePaths = paths(relativePath: relativePath)
        return values(paths: absolutePaths)
    }

    /// Get the json parents for the values found using the relative path @relativePath
    /// - parameter relativePath: The target json's relative path
    /// - parameter value: the json value from relative path @relativePath
    public func getParentValuesFor(relativePath relativePath: [SubscriptType], withValue value: JSON) -> [JSON] {
        let absolutePaths = paths(relativePath: relativePath)
        let filteredAbsolutePaths = absolutePaths.filter({ (path) -> Bool in
            return self[path] == value
        })
        let parentAbsolutePaths = filteredAbsolutePaths.map { (path) -> [SubscriptType] in
            var path = path
            if path.count == 0 {
                return []
            }
            path.removeLast()
            return path
        }
        return values(paths: parentAbsolutePaths)
    }

    /// Get the json value found using the relative path @relativePath from @index
    /// - parameter index: the index of the json value from the values found with the relative path
    /// - parameter relativePath: the target json's relative path
    public func getValueFromIndex(index: Int, relativePath: [SubscriptType]) -> JSON {
        var jsonValues = values(relativePath: relativePath)

        if jsonValues.count == index {
            XCTFail("A value from \(index) index was not found for relative json path \(relativePath) field in json:\n\(self)")
            return JSON.nullJSON
        }

        return jsonValues[index]
    }

    /// Get the first json value found using the relative path @relativePath
    /// - parameter relativePath: The target json's relative path
    public func getFirstValue(relativePath relativePath: [SubscriptType]) -> JSON {
        return getValueFromIndex(0, relativePath: relativePath)
    }

    /// Sets the values of a field found using a relative path @relativePath
    /// - parameter relativePath: The target json's relative path
    /// - parameter newValues: The new values used to update the fields found
    /// - returns: Returns the current json instance
    public mutating func updateValues(relativePath relativePath: [SubscriptType], newValues: [JSON]) -> JSON {
        let absolutePaths = paths(relativePath: relativePath)
        if absolutePaths.count != newValues.count {
            XCTFail("Found absolute paths count \(absolutePaths.count) doesn't match the new values count \(newValues.count) to set! Please, correct the relative path or update the new values.")
        }
        for index in 0 ..< absolutePaths.count {
            let path = absolutePaths[index]
            self[path] = newValues[index]
        }
        return self
    }

    /// Convert JSON values @values to an array of type @T? where T is a JSON accepted type: String, Int, Bool, Dictionary, Array
    public static func optionalValues<T>(values: [JSON]) -> [T?] {
        var toValues = [T?]()
        for value in values {
            if let error = value.error {
                XCTFail("Couldn't convert JSON value \(value) to type \(String(T?)) . Json error: \(error)")
            }
            if value != JSON.nullJSON {
                toValues.append(value.object as? T)
            } else {
                toValues.append(nil)
            }
        }
        return toValues
    }

    /// Convert JSON values @values to an array of type @T where T is a JSON accepted type: String, Int, Bool, Dictionary, Array
    public static func values<T>(values: [JSON]) -> [T] {
        var toValues = [T]()
        let optValues: [T?] = optionalValues(values)
        for optionalValue in optValues {
            if let value = optionalValue {
                toValues.append(value)
            } else {
                XCTFail("Couldn't convert JSON value \(optionalValue) to type \(String(T)).")
            }
        }
        return toValues
    }
}

private func ==(left: SubscriptType, right: SubscriptType) -> Bool {
    if (left is Int && right is String) || (left is String && right is Int) {
        return false
    }
    return String(left) == String(right)
}

private func !=(left: SubscriptType, right: SubscriptType) -> Bool {
    return !(left == right)
}

public func ==(left: [SubscriptType], right: [SubscriptType]) -> Bool {
    return String(left) == String(right)
}

/// Update the @jsonPath json path with placeholder values @placeholderValues . For e.g:
///
/// let jsonPath: [SubscriptType] = ["test1", "$test2", "test3"]
/// let updatedJsonPath = updateJsonPath(jsonPath, withPlaceholderValues: 1)
///
/// => updatedJsonPath will contain ["test1", 1, "test3"]
///
/// - parameter jsonPath the json path to update.
/// - parameter placeholderPrefix: the prefix string used to identify the placeholders from json path. The default prefix is "$".
/// - parameter withPlaceholderValues: the SubscriptType values in the right order for replacing the placeholders found in json path.
/// - returns: the updated json path.
public func updateJsonPath(jsonPath: [SubscriptType], placeholderPrefix: String = "$", withPlaceholderValues placeholderValues: SubscriptType...) -> [SubscriptType] {
    var jsonPath = jsonPath
    let originalJsonPath = jsonPath
    var actualPlaceholdersCount = 0
    for i in 0 ..< jsonPath.count {
        let field = jsonPath[i]
        if let fieldString = field as? String {
            if fieldString.hasPrefix(placeholderPrefix) {
                actualPlaceholdersCount += 1
                if placeholderValues.count < actualPlaceholdersCount {
                    XCTFail("There is no placeholder value passed for placeholder \(fieldString)")
                }
                jsonPath.replaceRange(i...i, with: [placeholderValues[actualPlaceholdersCount - 1]])
            }
        }
    }
    if placeholderValues.count > actualPlaceholdersCount {
        XCTFail("There are too many placeholder values passed to the function: original json path \(originalJsonPath) with \(actualPlaceholdersCount) placeholders, the expected placeholder values: \(placeholderValues)")
    }
    return jsonPath
}