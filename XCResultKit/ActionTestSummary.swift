//
//  ActionTestSummary.swift
//  
//
//  Created by David House on 7/5/19.
//
//- ActionTestSummary
//    * Supertype: ActionTestSummaryIdentifiableObject
//* Kind: object
//* Properties:
//+ summaries: [ActionTestPlanRunSummary]

import Foundation

public struct ActionTestSummary: XCResultObject {
    public let summaries: [ActionTestPlanRunSummary]

    public init?(_ json: [String : AnyObject]) {
        summaries = xcArray(element: "summaries", from: json).compactMap { ActionTestPlanRunSummary($0) }
    }
}
