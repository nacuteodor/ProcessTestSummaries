//
//  File.swift
//  
//
//  Created by David House on 7/3/19.
//
//- ActionTestPlanRunSummary
//    * Supertype: ActionAbstractTestSummary
//* Kind: object
//* Properties:
//+ testableSummaries: [ActionTestableSummary]

import Foundation

public struct ActionTestPlanRunSummary: XCResultObject {
    public var name: String
    public let testableSummaries: [ActionTestableSummary]
    
    public init?(_ json: [String : AnyObject]) {
        do {
            name = try xcRequired(element: "name", from: json)
            testableSummaries = xcArray(element: "testableSummaries", from: json).compactMap { ActionTestableSummary($0) }
        } catch {
            print("Error parsing ActionTestMetadata: \(error.localizedDescription)")
            return nil
        }
    }
}
