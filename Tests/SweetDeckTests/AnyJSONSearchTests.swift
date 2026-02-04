import XCTest
import SweetDeckInfra

final class AnyJSONSearchTests: XCTestCase {
    func testFindFirstDictionaryWithKeys() {
        let any: Any = [
            "a": [
                "b": [
                    "TARGET_BUILD_DIR": "/tmp",
                    "FULL_PRODUCT_NAME": "App.app",
                ],
            ],
        ]
        let dict = SweetDeckAnyJSONSearch.findFirstDictionary(any, whereKeysExist: ["TARGET_BUILD_DIR"])!
        XCTAssertEqual(dict["FULL_PRODUCT_NAME"] as? String, "App.app")
    }
}

