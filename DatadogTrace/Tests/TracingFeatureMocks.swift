/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import TestUtilities
import DatadogInternal

@testable import DatadogTrace

// MARK: - Span Mocks

extension DDSpanContext {
    static func mockAny() -> DDSpanContext {
        return mockWith()
    }

    static func mockWith(
        traceID: TraceID = .mockAny(),
        spanID: TraceID = .mockAny(),
        parentSpanID: TraceID? = .mockAny(),
        baggageItems: BaggageItems = .mockAny()
    ) -> DDSpanContext {
        return DDSpanContext(
            traceID: traceID,
            spanID: spanID,
            parentSpanID: parentSpanID,
            baggageItems: baggageItems
        )
    }
}

extension BaggageItems {
    static func mockAny() -> BaggageItems {
        return BaggageItems()
    }
}

extension DDSpan {
    static func mockAny(in core: DatadogCoreProtocol) -> DDSpan {
        return mockWith(core: core)
    }

    static func mockWith(
        tracer: DatadogTracer,
        context: DDSpanContext = .mockAny(),
        operationName: String = .mockAny(),
        startTime: Date = .mockAny(),
        tags: [String: Encodable] = [:]
    ) -> DDSpan {
        return DDSpan(
            tracer: tracer,
            context: context,
            operationName: operationName,
            startTime: startTime,
            tags: tags
        )
    }

    static func mockWith(
        core: DatadogCoreProtocol,
        context: DDSpanContext = .mockAny(),
        operationName: String = .mockAny(),
        startTime: Date = .mockAny(),
        tags: [String: Encodable] = [:]
    ) -> DDSpan {
        return DDSpan(
            tracer: .mockAny(in: core),
            context: context,
            operationName: operationName,
            startTime: startTime,
            tags: tags
        )
    }
}

extension SpanEvent: AnyMockable, RandomMockable {
    static func mockWith(
        traceID: TraceID = .mockAny(),
        spanID: TraceID = .mockAny(),
        parentID: TraceID? = .mockAny(),
        operationName: String = .mockAny(),
        serviceName: String = .mockAny(),
        resource: String = .mockAny(),
        startTime: Date = .mockAny(),
        duration: TimeInterval = .mockAny(),
        isError: Bool = .mockAny(),
        source: String = .mockAny(),
        origin: String? = nil,
        samplingRate: Float = 100,
        isKept: Bool = true,
        tracerVersion: String = .mockAny(),
        applicationVersion: String = .mockAny(),
        networkConnectionInfo: NetworkConnectionInfo? = .mockAny(),
        mobileCarrierInfo: CarrierInfo? = .mockAny(),
        userInfo: SpanEvent.UserInfo = .mockAny(),
        tags: [String: String] = [:]
    ) -> SpanEvent {
        return SpanEvent(
            traceID: traceID,
            spanID: spanID,
            parentID: parentID,
            operationName: operationName,
            serviceName: serviceName,
            resource: resource,
            startTime: startTime,
            duration: duration,
            isError: isError,
            source: source,
            origin: origin,
            samplingRate: samplingRate,
            isKept: isKept,
            tracerVersion: tracerVersion,
            applicationVersion: applicationVersion,
            networkConnectionInfo: networkConnectionInfo,
            mobileCarrierInfo: mobileCarrierInfo,
            userInfo: userInfo,
            tags: tags
        )
    }

    public static func mockAny() -> SpanEvent { .mockWith() }

    public static func mockRandom() -> SpanEvent {
        return SpanEvent(
            traceID: .init(rawValue: .mockRandom()),
            spanID: .init(rawValue: .mockRandom()),
            parentID: .init(rawValue: .mockRandom()),
            operationName: .mockRandom(),
            serviceName: .mockRandom(),
            resource: .mockRandom(),
            startTime: .mockRandomInThePast(),
            duration: .mockRandom(),
            isError: .random(),
            source: .mockRandom(),
            origin: .mockRandom(),
            samplingRate: .mockRandom(),
            isKept: .mockRandom(),
            tracerVersion: .mockRandom(),
            applicationVersion: .mockRandom(),
            networkConnectionInfo: .mockRandom(),
            mobileCarrierInfo: .mockRandom(),
            userInfo: .mockRandom(),
            tags: .mockRandom()
        )
    }
}

extension SpanEvent.UserInfo: AnyMockable, RandomMockable {
    static func mockWith(
        id: String? = .mockAny(),
        name: String? = .mockAny(),
        email: String? = .mockAny(),
        extraInfo: [String: String] = [:]
    ) -> SpanEvent.UserInfo {
        return SpanEvent.UserInfo(
            id: id,
            name: name,
            email: email,
            extraInfo: extraInfo
        )
    }

    public static func mockAny() -> SpanEvent.UserInfo { .mockWith() }

    public static func mockRandom() -> SpanEvent.UserInfo {
        return SpanEvent.UserInfo(
            id: .mockRandom(),
            name: .mockRandom(),
            email: .mockRandom(),
            extraInfo: .mockRandom()
        )
    }
}

// MARK: - Component Mocks

extension DatadogTracer {
    static func mockAny(in core: DatadogCoreProtocol) -> Self {
        return mockWith(core: core)
    }

    static func mockWith(
        core: DatadogCoreProtocol,
        configuration: Configuration = .init(),
        tracingUUIDGenerator: TraceIDGenerator = DefaultTraceIDGenerator(),
        dateProvider: DateProvider = SystemDateProvider()
    ) -> Self {
        return .init(
            core: core,
            configuration: configuration,
            tracingUUIDGenerator: tracingUUIDGenerator,
            dateProvider: dateProvider,
            contextReceiver: ContextMessageReceiver(bundleWithRUM: configuration.bundleWithRUM),
            loggingIntegration: .init(core: core, tracerConfiguration: configuration)
        )
    }
}

extension SpanEventBuilder {
    static func mockAny() -> SpanEventBuilder {
        return mockWith()
    }

    static func mockWith(
        serviceName: String = .mockAny(),
        sendNetworkInfo: Bool = false,
        eventsMapper: SpanEventMapper? = nil
    ) -> SpanEventBuilder {
        return SpanEventBuilder(
            serviceName: serviceName,
            sendNetworkInfo: sendNetworkInfo,
            eventsMapper: eventsMapper
        )
    }
}

extension TracingWithLoggingIntegration.Configuration: AnyMockable {
    public static func mockAny() -> TracingWithLoggingIntegration.Configuration {
        .init(
            service: .mockAny(),
            loggerName: .mockAny(),
            sendNetworkInfo: true
        )
    }
}
