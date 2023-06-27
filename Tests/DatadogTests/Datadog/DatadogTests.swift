/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities

@testable import DatadogInternal
@testable import DatadogLogs
@testable import DatadogTrace
@testable import Datadog

class DatadogTests: XCTestCase {
    private var printFunction: PrintFunctionMock! // swiftlint:disable:this implicitly_unwrapped_optional
    private var defaultConfig = DatadogCore.Configuration(clientToken: "abc-123", env: "tests")

    override func setUp() {
        super.setUp()

        XCTAssertFalse(DatadogCore.isInitialized)
        printFunction = PrintFunctionMock()
        consolePrint = printFunction.print
    }

    override func tearDown() {
        consolePrint = { print($0) }
        printFunction = nil
        XCTAssertFalse(DatadogCore.isInitialized)
        super.tearDown()
    }

    // MARK: - Initializing with different configurations

    func testDefaultConfiguration() throws {
        var configuration = defaultConfig

        configuration.bundle = .mockWith(
            bundleIdentifier: "test",
            CFBundleShortVersionString: "1.0.0",
            CFBundleExecutable: "Test"
        )

        XCTAssertEqual(configuration.batchSize, .medium)
        XCTAssertEqual(configuration.uploadFrequency, .average)
        XCTAssertEqual(configuration.additionalConfiguration.count, 0)
        XCTAssertNil(configuration.encryption)
        XCTAssertTrue(configuration.serverDateProvider is DatadogNTPDateProvider)

        DatadogCore.initialize(
            with: configuration,
            trackingConsent: .granted
        )
        defer { DatadogCore.flushAndDeinitialize() }

        let core = try XCTUnwrap(CoreRegistry.default as? Core)
        XCTAssertTrue(core.dateProvider is SystemDateProvider)
        XCTAssertNil(core.httpClient.session.configuration.connectionProxyDictionary)
        XCTAssertNil(core.encryption)

        let context = core.contextProvider.read()
        XCTAssertEqual(context.clientToken, "abc-123")
        XCTAssertEqual(context.env, "tests")
        XCTAssertEqual(context.site, .us1)
        XCTAssertEqual(context.service, "test")
        XCTAssertEqual(context.version, "1.0.0")
        XCTAssertEqual(context.sdkVersion, __sdkVersion)
        XCTAssertEqual(context.applicationName, "Test")
        XCTAssertNil(context.variant)
        XCTAssertEqual(context.source, "ios")
        XCTAssertEqual(context.applicationBundleIdentifier, "test")
        XCTAssertEqual(context.trackingConsent, .granted)
    }

    func testAdvancedConfiguration() throws {
        var configuration = defaultConfig

        configuration.service = "service-name"
        configuration.site = .eu1
        configuration.batchSize = .small
        configuration.uploadFrequency = .frequent
        configuration.proxyConfiguration = [
            kCFNetworkProxiesHTTPEnable: true,
            kCFNetworkProxiesHTTPPort: 123,
            kCFNetworkProxiesHTTPProxy: "www.example.com",
            kCFProxyUsernameKey: "proxyuser",
            kCFProxyPasswordKey: "proxypass",
        ]
        configuration.bundle = .mockWith(
            bundleIdentifier: "test",
            CFBundleShortVersionString: "1.0.0",
            CFBundleExecutable: "Test"
        )
        configuration.encryption = DataEncryptionMock()
        configuration.serverDateProvider = ServerDateProviderMock()
        configuration.additionalConfiguration = [
            CrossPlatformAttributes.ddsource: "cp-source",
            CrossPlatformAttributes.variant: "cp-variant",
            CrossPlatformAttributes.sdkVersion: "cp-version"
        ]

        XCTAssertEqual(configuration.batchSize, .small)
        XCTAssertEqual(configuration.uploadFrequency, .frequent)
        XCTAssertTrue(configuration.encryption is DataEncryptionMock)
        XCTAssertTrue(configuration.serverDateProvider is ServerDateProviderMock)

        DatadogCore.initialize(
            with: configuration,
            trackingConsent: .pending
        )
        defer { DatadogCore.flushAndDeinitialize() }

        let core = try XCTUnwrap(CoreRegistry.default as? Core)
        XCTAssertTrue(core.dateProvider is SystemDateProvider)
        XCTAssertTrue(core.encryption is DataEncryptionMock)

        let connectionProxyDictionary = try XCTUnwrap(core.httpClient.session.configuration.connectionProxyDictionary)
        XCTAssertEqual(connectionProxyDictionary[kCFNetworkProxiesHTTPEnable] as? Bool, true)
        XCTAssertEqual(connectionProxyDictionary[kCFNetworkProxiesHTTPPort] as? Int, 123)
        XCTAssertEqual(connectionProxyDictionary[kCFNetworkProxiesHTTPProxy] as? String, "www.example.com")
        XCTAssertEqual(connectionProxyDictionary[kCFProxyUsernameKey] as? String, "proxyuser")
        XCTAssertEqual(connectionProxyDictionary[kCFProxyPasswordKey] as? String, "proxypass")

        let context = core.contextProvider.read()
        XCTAssertEqual(context.clientToken, "abc-123")
        XCTAssertEqual(context.env, "tests")
        XCTAssertEqual(context.site, .eu1)
        XCTAssertEqual(context.service, "service-name")
        XCTAssertEqual(context.version, "1.0.0")
        XCTAssertEqual(context.sdkVersion, "cp-version")
        XCTAssertEqual(context.applicationName, "Test")
        XCTAssertEqual(context.variant, "cp-variant")
        XCTAssertEqual(context.source, "cp-source")
        XCTAssertEqual(context.applicationBundleIdentifier, "test")
        XCTAssertEqual(context.trackingConsent, .pending)
    }

    func testGivenDefaultConfiguration_itCanBeInitialized() {
        DatadogCore.initialize(
            with: defaultConfig,
            trackingConsent: .mockRandom()
        )
        XCTAssertTrue(DatadogCore.isInitialized)
        DatadogCore.flushAndDeinitialize()
    }

    func testGivenInvalidConfiguration_itPrintsError() {
        let invalidConfiguration = DatadogCore.Configuration(clientToken: "", env: "tests")

        DatadogCore.initialize(
            with: invalidConfiguration,
            trackingConsent: .mockRandom()
        )

        XCTAssertEqual(
            printFunction.printedMessage,
            "🔥 Datadog SDK usage error: `clientToken` cannot be empty."
        )
        XCTAssertFalse(DatadogCore.isInitialized)
    }

    func testGivenValidConfiguration_whenInitializedMoreThanOnce_itPrintsError() {
        DatadogCore.initialize(
            with: defaultConfig,
            trackingConsent: .mockRandom()
        )

        DatadogCore.initialize(
            with: defaultConfig,
            trackingConsent: .mockRandom()
        )

        XCTAssertEqual(
            printFunction.printedMessage,
            "🔥 Datadog SDK usage error: SDK is already initialized."
        )

        DatadogCore.flushAndDeinitialize()
    }

    // MARK: - Public APIs

    func testTrackingConsent() {
        let initialConsent: TrackingConsent = .mockRandom()
        let nextConsent: TrackingConsent = .mockRandom()

        DatadogCore.initialize(
            with: defaultConfig,
            trackingConsent: initialConsent
        )

        let core = CoreRegistry.default as? Core
        XCTAssertEqual(core?.consentPublisher.consent, initialConsent)

        DatadogCore.set(trackingConsent: nextConsent)

        XCTAssertEqual(core?.consentPublisher.consent, nextConsent)

        DatadogCore.flushAndDeinitialize()
    }

    func testUserInfo() {
        DatadogCore.initialize(
            with: defaultConfig,
            trackingConsent: .mockRandom()
        )

        let core = CoreRegistry.default as? Core

        XCTAssertNil(core?.userInfoPublisher.current.id)
        XCTAssertNil(core?.userInfoPublisher.current.email)
        XCTAssertNil(core?.userInfoPublisher.current.name)
        XCTAssertEqual(core?.userInfoPublisher.current.extraInfo as? [String: Int], [:])

        DatadogCore.setUserInfo(
            id: "foo",
            name: "bar",
            email: "foo@bar.com",
            extraInfo: ["abc": 123]
        )

        XCTAssertEqual(core?.userInfoPublisher.current.id, "foo")
        XCTAssertEqual(core?.userInfoPublisher.current.name, "bar")
        XCTAssertEqual(core?.userInfoPublisher.current.email, "foo@bar.com")
        XCTAssertEqual(core?.userInfoPublisher.current.extraInfo as? [String: Int], ["abc": 123])

        DatadogCore.flushAndDeinitialize()
    }

    func testAddUserPreoprties_mergesProperties() {
        DatadogCore.initialize(
            with: defaultConfig,
            trackingConsent: .mockRandom()
        )

        let core = CoreRegistry.default as? Core

        DatadogCore.setUserInfo(
            id: "foo",
            name: "bar",
            email: "foo@bar.com",
            extraInfo: ["abc": 123]
        )

        DatadogCore.addUserExtraInfo(["second": 667])

        XCTAssertEqual(core?.userInfoPublisher.current.id, "foo")
        XCTAssertEqual(core?.userInfoPublisher.current.name, "bar")
        XCTAssertEqual(core?.userInfoPublisher.current.email, "foo@bar.com")
        XCTAssertEqual(
            core?.userInfoPublisher.current.extraInfo as? [String: Int],
            ["abc": 123, "second": 667]
        )

        DatadogCore.flushAndDeinitialize()
    }

    func testAddUserPreoprties_removesProperties() {
        DatadogCore.initialize(
            with: defaultConfig,
            trackingConsent: .mockRandom()
        )

        let core = CoreRegistry.default as? Core

        DatadogCore.setUserInfo(
            id: "foo",
            name: "bar",
            email: "foo@bar.com",
            extraInfo: ["abc": 123]
        )

        DatadogCore.addUserExtraInfo(["abc": nil, "second": 667])

        XCTAssertEqual(core?.userInfoPublisher.current.id, "foo")
        XCTAssertEqual(core?.userInfoPublisher.current.name, "bar")
        XCTAssertEqual(core?.userInfoPublisher.current.email, "foo@bar.com")
        XCTAssertEqual(core?.userInfoPublisher.current.extraInfo as? [String: Int], ["second": 667])

        DatadogCore.flushAndDeinitialize()
    }

    func testAddUserPreoprties_overwritesProperties() {
        DatadogCore.initialize(
            with: defaultConfig,
            trackingConsent: .mockRandom()
        )

        let core = CoreRegistry.default as? Core

        DatadogCore.setUserInfo(
            id: "foo",
            name: "bar",
            email: "foo@bar.com",
            extraInfo: ["abc": 123]
        )

        DatadogCore.addUserExtraInfo(["abc": 444])

        XCTAssertEqual(core?.userInfoPublisher.current.id, "foo")
        XCTAssertEqual(core?.userInfoPublisher.current.name, "bar")
        XCTAssertEqual(core?.userInfoPublisher.current.email, "foo@bar.com")
        XCTAssertEqual(core?.userInfoPublisher.current.extraInfo as? [String: Int], ["abc": 444])

        DatadogCore.flushAndDeinitialize()
    }

    func testDefaultVerbosityLevel() {
        XCTAssertNil(DatadogCore.verbosityLevel)
    }

    func testGivenDataStoredInAllFeatureDirectories_whenClearAllDataIsUsed_allFilesAreRemoved() throws {
        DatadogCore.initialize(
            with: defaultConfig,
            trackingConsent: .mockRandom()
        )

        Logs.enable()
        Trace.enable()

        let core = try XCTUnwrap(CoreRegistry.default as? Core)

        // On SDK init, underlying `ConsentAwareDataWriter` performs data migration for each feature, which includes
        // data removal in `unauthorised` (`.pending`) directory. To not cause test flakiness, we must ensure that
        // mock data is written only after this operation completes - otherwise, migration may delete mocked files.
        core.readWriteQueue.sync {}

        let featureDirectories: [FeatureDirectories] = [
            try core.directory.getFeatureDirectories(forFeatureNamed: "logging"),
            try core.directory.getFeatureDirectories(forFeatureNamed: "tracing"),
        ]

        let allDirectories: [Directory] = featureDirectories.flatMap { [$0.authorized, $0.unauthorized] }
        try allDirectories.forEach { directory in _ = try directory.createFile(named: .mockRandom()) }

        // Given
        let numberOfFiles = try allDirectories.reduce(0, { acc, nextDirectory in return try acc + nextDirectory.files().count })
        XCTAssertEqual(numberOfFiles, 4, "Each feature stores 2 files - one authorised and one unauthorised")

        // When
        DatadogCore.clearAllData()

        // Wait for async clear completion in all features:
        core.readWriteQueue.sync {}

        // Then
        let newNumberOfFiles = try allDirectories.reduce(0, { acc, nextDirectory in return try acc + nextDirectory.files().count })
        XCTAssertEqual(newNumberOfFiles, 0, "All files must be removed")

        DatadogCore.flushAndDeinitialize()
    }

    func testServerDateProvider() throws {
        // Given
        var config = defaultConfig
        let serverDateProvider = ServerDateProviderMock()
        config.serverDateProvider = serverDateProvider

        // When
        DatadogCore.initialize(
            with: config,
            trackingConsent: .mockRandom()
        )

        serverDateProvider.offset = -1

        // Then
        let core = try XCTUnwrap(CoreRegistry.default as? Core)
        let context = core.contextProvider.read()
        XCTAssertEqual(context.serverTimeOffset, -1)

        DatadogCore.flushAndDeinitialize()
    }

    func testRemoveV1DeprecatedFolders() throws {
        // Given
        let cache = try Directory.cache()
        let directories = ["com.datadoghq.logs", "com.datadoghq.traces", "com.datadoghq.rum"]
        try directories.forEach {
            _ = try cache.createSubdirectory(path: $0).createFile(named: "test")
        }

        // When
        DatadogCore.initialize(
            with: defaultConfig,
            trackingConsent: .mockRandom()
        )

        defer { DatadogCore.flushAndDeinitialize() }

        let core = try XCTUnwrap(CoreRegistry.default as? Core)
        // Wait for async deletion
        core.readWriteQueue.sync {}

        // Then
        XCTAssertThrowsError(try cache.subdirectory(path: "com.datadoghq.logs"))
        XCTAssertThrowsError(try cache.subdirectory(path: "com.datadoghq.traces"))
        XCTAssertThrowsError(try cache.subdirectory(path: "com.datadoghq.rum"))
    }

    func testCustomSDKInstance() throws {
        // When
        DatadogCore.initialize(
            with: defaultConfig,
            trackingConsent: .mockRandom(),
            instanceName: "test"
        )

        defer { DatadogCore.flushAndDeinitialize(instanceName: "test") }

        // Then
        XCTAssertTrue(CoreRegistry.default is NOPDatadogCore)
        XCTAssertTrue(CoreRegistry.instance(named: "test") is Core)
    }
}
