import AVFAudio
import XCTest
@testable import CallMe

final class CallExperimentRulesTests: XCTestCase {
    func testRejectsBlankNameAndEmergencyNumber() {
        XCTAssertNotNil(CallExperimentRules.callerNameError("   "))
        XCTAssertEqual(CallExperimentRules.callerNumberError("9-1-1"), "请勿使用紧急号码")
        XCTAssertNil(CallExperimentRules.callerNumberError("010-5555-0123"))
    }

    func testDelayIsLimitedToTwentyFourHours() {
        XCTAssertEqual(CallExperimentRules.customDelay("30", unit: .seconds), 30)
        XCTAssertEqual(CallExperimentRules.customDelay("1", unit: .minutes), 60)
        XCTAssertEqual(CallExperimentRules.customDelay("24", unit: .hours), 86_400)
        XCTAssertEqual(CallExperimentRules.customDelay("1440", unit: .minutes), 86_400)
        XCTAssertNil(CallExperimentRules.customDelay("86401", unit: .seconds))
        XCTAssertNil(CallExperimentRules.customDelay("25", unit: .hours))
        XCTAssertEqual(CallExperimentRules.delayDescription(60), "1 分钟")
        XCTAssertEqual(CallExperimentRules.delayDescription(86_400), "24 小时")
    }

    func testRingtoneResourceMapping() {
        XCTAssertNil(IncomingRingtone.system.resourceName)
        XCTAssertEqual(IncomingRingtone.wechatClassic.resourceName, "WeChatClassic.mp3")
        XCTAssertEqual(IncomingRingtone.callMe.resourceName, "CallMeRingtone.wav")
        XCTAssertEqual(IncomingRingtone.chatClassic.resourceName, "ChatClassic.wav")
        XCTAssertEqual(IncomingRingtone.chatCrystal.resourceName, "ChatCrystal.wav")
        XCTAssertEqual(IncomingRingtone.chatMinimal.resourceName, "ChatMinimal.wav")
        XCTAssertNil(IncomingRingtone.custom.resourceName)
    }

    func testWechatClassicAudioIsBundledAndDecodable() throws {
        let resourceURL = try XCTUnwrap(
            Bundle.main.url(forResource: "WeChatClassic", withExtension: "mp3")
        )
        let player = try AVAudioPlayer(contentsOf: resourceURL)

        XCTAssertTrue(player.prepareToPlay())
        XCTAssertEqual(player.duration, 4.44, accuracy: 0.1)
    }

    func testCallStylesProduceExpectedPresentationRules() {
        XCTAssertFalse(IncomingCallStyle.wechatVoice.hasVideo)
        XCTAssertTrue(IncomingCallStyle.wechatVideo.hasVideo)
        XCTAssertFalse(IncomingCallStyle.phone.usesCustomForegroundUI)
        XCTAssertTrue(IncomingCallStyle.wechatVoice.usesCustomForegroundUI)
        XCTAssertTrue(IncomingCallStyle.wechatVideo.usesCustomForegroundUI)
        XCTAssertEqual(
            IncomingCallStyle.phone.effectiveRingtone(selected: .system),
            .system
        )
        XCTAssertEqual(
            IncomingCallStyle.wechatVoice.effectiveRingtone(selected: .system),
            .wechatClassic
        )
        XCTAssertEqual(
            IncomingCallStyle.wechatVideo.effectiveRingtone(selected: .chatCrystal),
            .chatCrystal
        )
        XCTAssertEqual(
            IncomingCallStyle.wechatVoice.effectiveRingtone(selected: .custom),
            .wechatClassic
        )
    }

    func testTemplateRestoresStyleAndRingtone() {
        let template = CallTemplate(
            id: UUID(),
            callerName: "老板",
            callerNumber: "13800138000",
            callerAvatarData: Data(),
            styleRawValue: IncomingCallStyle.wechatVideo.rawValue,
            delay: 180,
            ringtoneRawValue: IncomingRingtone.callMe.rawValue,
            updatedAt: Date()
        )
        XCTAssertEqual(template.style, .wechatVideo)
        XCTAssertEqual(template.ringtone, .callMe)
        XCTAssertEqual(template.delay, 180)
    }

    func testEventHistoryKeepsNewestTwoHundredEntries() {
        let events = (0..<250).map { "event-\($0)" }
        let normalized = CallEventHistory.normalized(events)

        XCTAssertEqual(normalized.count, 200)
        XCTAssertEqual(normalized.first, "event-0")
        XCTAssertEqual(normalized.last, "event-199")
    }
}
