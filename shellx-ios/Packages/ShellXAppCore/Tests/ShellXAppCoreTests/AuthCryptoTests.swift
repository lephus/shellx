import XCTest
@testable import ShellXAppCore

final class AuthCryptoTests: XCTestCase {
    func testPKCEChallengeMatchesRFC7636AppendixB() {
        XCTAssertEqual(
            AuthCrypto.pkceChallenge(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
            "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }
    func testSHA256HexIsLowercaseHex() {
        XCTAssertEqual(AuthCrypto.sha256Hex("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
    func testBase64URLUsesTheURLAlphabetWithoutPadding() {
        XCTAssertEqual(AuthCrypto.base64URL(Data([0xFB, 0xFF, 0xBF])), "-_-_")
        XCTAssertEqual(AuthCrypto.base64URL(Data([0x61])), "YQ")
    }
    func testRandomTokensAre43URLSafeCharactersAndDiffer() {
        let a = AuthCrypto.randomToken(), b = AuthCrypto.randomToken()
        XCTAssertEqual(a.count, 43)
        XCTAssertNotEqual(a, b)
        XCTAssertTrue(a.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
    }
}
