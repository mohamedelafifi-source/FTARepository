//
//  MyFamilyTreeTests.swift
//  MyFamilyTreeTests
//
//  Created by Mohamed El Afifi on 9/30/25.
//
/*
import Testing
@testable import MyFamilyTree

struct MyFamilyTreeTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

}
*/
//New test 
import XCTest
@testable import MyFamilyTree  // <-- must match your app’s module name

final class MyFamilyTreeTests: XCTestCase {
    func testSmoke() {
        XCTAssertTrue(true)
    }
}
