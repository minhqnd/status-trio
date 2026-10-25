import AppKit
import XCTest
@testable import StatusTrioCore

/// Temporary source feedback needs event observation even with the network centre.
@MainActor
final class InputSourceMonitoringLifecycleTests: XCTestCase {
    func testMonitoringStaysAvailableForTransientFeedbackWithoutRepeatedReads() throws {
        let suiteName = "InputSourceMonitoringLifecycleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = SettingsStore(defaults: defaults)
        settings.hasCompletedIconGuideOnboarding = true
        let reader = CountingInputSourceReader()
        let controller = InputSourceController(reader: reader)
        let environment = makeEnvironment(
            settings: settings,
            defaults: defaults,
            controller: controller
        )
        defer { environment.stop() }

        environment.start()
        XCTAssertEqual(reader.readCount, 1, "start reads once to establish the baseline")

        settings.connectionCenterSource = .inputSource
        XCTAssertEqual(reader.readCount, 1)
        XCTAssertEqual(controller.state.selectedID, CountingInputSourceReader.abcID)

        settings.connectionCenterSource = .automatic
        XCTAssertEqual(reader.readCount, 1, "the network centre still needs change feedback")

        settings.setPopupSection(.inputSource, enabled: true)
        XCTAssertEqual(reader.readCount, 1, "settings changes reuse the event observer")

        settings.setPopupSection(.inputSource, enabled: false)
        XCTAssertEqual(reader.readCount, 1, "no extra reads while idle")
        environment.stop()
        controller.start()
        XCTAssertEqual(reader.readCount, 2, "environment stop must remove the observer lifecycle")
        controller.stop()
    }

    private func makeEnvironment(
        settings: SettingsStore,
        defaults: UserDefaults,
        controller: InputSourceController
    ) -> AppEnvironment {
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        let store = AppEnvironment.makeStore(
            batteryMonitor: LifecycleStubBatteryMonitor(),
            wifiMonitor: LifecycleStubWiFiMonitor(),
            volumeMonitor: LifecycleStubVolumeMonitor()
        )
        let clock = ChargingEffectClock()
        let application = LifecycleStubApplication()
        let activationPolicy = AppActivationPolicy(application: application)
        let iconPresentation = makeTestIconPresentation(store: store, settings: settings)

        return AppEnvironment(
            store: store,
            settings: settings,
            localization: localization,
            iconPresentation: iconPresentation,
            statusBarController: StatusBarController(
                store: store,
                settings: settings,
                iconPresentation: iconPresentation,
                localization: localization,
                isVisible: false,
                openSettings: {},
                quitAction: {},
                chargingEffectClock: clock,
                renderMenuBarBase: { _, _, _, _ in nil },
                inputSourceController: controller
            ),
            settingsWindowController: SettingsWindowController(
                store: settings,
                statusStore: store,
                localization: localization,
                activationPolicy: activationPolicy,
                showIconGuide: {},
                chargingEffectClock: clock,
                inputSourceController: controller
            ),
            onboardingWindowController: OnboardingWindowController(
                settings: settings,
                localization: localization,
                activationPolicy: activationPolicy
            ),
            activationPolicy: activationPolicy,
            appIconController: AppIconController(
                settings: settings,
                iconPresentation: iconPresentation,
                activationPolicy: activationPolicy,
                application: application,
                setMenuBarVisible: { _ in },
                renderDockIcon: { _, _, _ in nil },
                theme: { .default },
                isDarkAppearance: { false },
                notificationCenter: NotificationCenter()
            ),
            mainMenuController: MainMenuController(
                activationPolicy: activationPolicy,
                localization: localization,
                notificationCenter: NotificationCenter(),
                openSettings: {}
            ),
            inputSourceController: controller,
            chargingEffectClock: clock,
            chargingEffectMotionMonitor: ChargingEffectMotionMonitor(
                readReduceMotion: { false },
                notificationCenter: NotificationCenter()
            ),
            telemetryReporter: LifecycleStubTelemetryReporter()
        )
    }
}

/// Counts reads so settings changes cannot accidentally restart monitoring.
private final class CountingInputSourceReader: InputSourceReading {
    static let abcID = "com.apple.keylayout.ABC"
    static let pinyinID = "com.tencent.inputmethod.wetype.pinyin"

    private(set) var readCount = 0

    func currentKeyboardInputSourceID() -> String? { Self.abcID }

    func keyboardInputSources() -> [RawInputSource] {
        readCount += 1
        return [
            RawInputSource(
                id: Self.abcID,
                localizedName: "ABC",
                languages: ["en"],
                iconImageURL: nil,
                isEnabled: true,
                isSelectCapable: true
            )
        ]
    }
}

@MainActor
private final class LifecycleStubTelemetryReporter: TelemetryReporting {
    func start() {}
    func stop() {}
}

@MainActor
private final class LifecycleStubApplication: ApplicationActivationPolicyApplying, ApplicationDockIconApplying {
    private(set) var currentActivationPolicy: NSApplication.ActivationPolicy = .accessory
    func setActivationPolicy(_ activationPolicy: NSApplication.ActivationPolicy) -> Bool { true }
    func setApplicationIconImage(_ image: NSImage?) {}
}

@MainActor
private final class LifecycleStubBatteryMonitor: BatteryMonitoring {
    let updates = AsyncStream<BatteryStatus> { $0.finish() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}

@MainActor
private final class LifecycleStubWiFiMonitor: WiFiMonitoring {
    let updates = AsyncStream<WiFiStatus> { $0.finish() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
    func requestNameAccess() -> WiFiNameAccessRequestResult { .notNeeded }
}

@MainActor
private final class LifecycleStubVolumeMonitor: VolumeMonitoring {
    let updates = AsyncStream<VolumeStatus> { $0.finish() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}
