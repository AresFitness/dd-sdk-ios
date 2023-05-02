/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(tvOS)

import XCTest
import WebKit
@testable import TestUtilities
@testable import DatadogInternal
@testable import DatadogWebViewTracking

final class DDUserContentController: WKUserContentController {
    typealias NameHandlerPair = (name: String, handler: WKScriptMessageHandler)
    private(set) var messageHandlers = [NameHandlerPair]()

    override func add(_ scriptMessageHandler: WKScriptMessageHandler, name: String) {
        messageHandlers.append((name: name, handler: scriptMessageHandler))
    }

    override func removeScriptMessageHandler(forName name: String) {
        messageHandlers = messageHandlers.filter {
            return $0.name != name
        }
    }
}

final class MockMessageHandler: NSObject, WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) { }
}

final class MockScriptMessage: WKScriptMessage {
    let mockBody: Any

    init(body: Any) {
        self.mockBody = body
    }

    override var body: Any { return mockBody }
}

class WKUserContentController_DatadogTests: XCTestCase {
    func testItAddsUserScriptAndMessageHandler() throws {
        let mockSanitizer = HostsSanitizerMock()
        let controller = DDUserContentController()

        let initialUserScriptCount = controller.userScripts.count

        controller.addDatadogMessageHandler(
            core: PassthroughCoreMock(),
            allowedWebViewHosts: ["datadoghq.com"],
            hostsSanitizer: mockSanitizer
        )

        XCTAssertEqual(controller.userScripts.count, initialUserScriptCount + 1)
        XCTAssertEqual(controller.messageHandlers.map({ $0.name }), ["DatadogEventBridge"])

        XCTAssertEqual(mockSanitizer.sanitizations.count, 1)
        let sanitization = try XCTUnwrap(mockSanitizer.sanitizations.first)
        XCTAssertEqual(sanitization.hosts, ["datadoghq.com"])
        XCTAssertEqual(sanitization.warningMessage, "The allowed WebView host configured for Datadog SDK is not valid")
    }

    func testWhenAddingMessageHandlerMultipleTimes_itIgnoresExtraOnesAndPrintsWarning() throws {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        let mockSanitizer = HostsSanitizerMock()
        let controller = DDUserContentController()

        let initialUserScriptCount = controller.userScripts.count

        let multipleTimes = 5
        (0..<multipleTimes).forEach { _ in
            controller.addDatadogMessageHandler(
                core: PassthroughCoreMock(),
                allowedWebViewHosts: ["datadoghq.com"],
                hostsSanitizer: mockSanitizer
            )
        }

        XCTAssertEqual(controller.userScripts.count, initialUserScriptCount + 1)
        XCTAssertEqual(controller.messageHandlers.map({ $0.name }), ["DatadogEventBridge"])

        XCTAssertGreaterThanOrEqual(mockSanitizer.sanitizations.count, 1)
        let sanitization = try XCTUnwrap(mockSanitizer.sanitizations.first)
        XCTAssertEqual(sanitization.hosts, ["datadoghq.com"])
        XCTAssertEqual(sanitization.warningMessage, "The allowed WebView host configured for Datadog SDK is not valid")

        XCTAssertEqual(
            dd.logger.warnLogs.map({ $0.message }),
            Array(repeating: "`startTrackingDatadogEvents(core:hosts:)` was called more than once for the same WebView. Second call will be ignored. Make sure you call it only once.", count: multipleTimes - 1)
        )
    }

    func testWhenStoppingTracking_itKeepsNonDatadogComponents() throws {
        let core = PassthroughCoreMock()
        let controller = DDUserContentController()

        controller.startTrackingDatadogEvents(core: core, hosts: [])

        let componentCount = 10
        for i in 0..<componentCount {
            let userScript = WKUserScript(
                source: String.mockRandom(),
                injectionTime: (i % 2 == 0 ? .atDocumentStart : .atDocumentEnd),
                forMainFrameOnly: i % 2 == 0
            )
            controller.addUserScript(userScript)
            controller.add(MockMessageHandler(), name: String.mockRandom())
        }

        XCTAssertEqual(controller.userScripts.count, componentCount + 1)
        XCTAssertEqual(controller.messageHandlers.count, componentCount + 1)

        controller.stopTrackingDatadogEvents()

        XCTAssertEqual(controller.userScripts.count, componentCount)
        XCTAssertEqual(controller.messageHandlers.count, componentCount)
    }

    func testItLogsInvalidWebMessages() throws {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        let controller = DDUserContentController()
        controller.addDatadogMessageHandler(
            core: PassthroughCoreMock(),
            allowedWebViewHosts: ["datadoghq.com"],
            hostsSanitizer: HostsSanitizerMock()
        )

        let messageHandler = try XCTUnwrap(controller.messageHandlers.first?.handler) as? DatadogMessageHandler
        // non-string body is passed
        messageHandler?.userContentController(controller, didReceive: MockScriptMessage(body: 123))
        messageHandler?.queue.sync { }

        XCTAssertEqual(dd.logger.errorLog?.message, "Encountered an error when receiving web view event")
        XCTAssertEqual(dd.logger.errorLog?.error?.message, #"invalidMessage(description: "123")"#)
    }

    func testSendingWebEvents() throws {
        let logMessageExpectation = expectation(description: "Log message received")
        let rumMessageExpectation = expectation(description: "RUM message received")
        let core = PassthroughCoreMock(
            messageReceiver: FeatureMessageReceiverMock { message in
                switch message {
                case .custom(key: let key, baggage: let baggage):
                    switch key {
                    case "browser-log":
                        let event = baggage.attributes as JSON
                        XCTAssertEqual(event["date"] as? Int64, 1_635_932_927_012)
                        XCTAssertEqual(event["message"] as? String, "console error: error")
                        XCTAssertEqual(event["status"] as? String, "error")
                        XCTAssertEqual(event["view"] as? [String: String], ["referrer": "", "url": "https://datadoghq.dev/browser-sdk-test-playground"])
                        XCTAssertEqual(event["error"] as? [String : String], ["origin": "console"])
                        XCTAssertEqual(event["session_id"] as? String, "0110cab4-7471-480e-aa4e-7ce039ced355")
                        logMessageExpectation.fulfill()
                    case "browser-rum-event":
                        let event = baggage.attributes as JSON
                        XCTAssertEqual((event["view"] as? JSON)?["id"] as? String, "64308fd4-83f9-48cb-b3e1-1e91f6721230")
                        rumMessageExpectation.fulfill()
                    default:
                        XCTFail("Unexpected custom message received: key: \(key), baggage: \(baggage)")
                    }
                    break
                case .context:
                    break
                default:
                    XCTFail("Unexpected message received: \(message)")
                }
            }
        )

        let controller = DDUserContentController()
        controller.addDatadogMessageHandler(
            core: core,
            allowedWebViewHosts: ["datadoghq.com"],
            hostsSanitizer: HostsSanitizerMock()
        )

        let messageHandler = try XCTUnwrap(controller.messageHandlers.first?.handler) as? DatadogMessageHandler
        let webLogMessage = MockScriptMessage(body: """
        {
          "eventType": "log",
          "event": {
            "date": 1635932927012,
            "error": {
              "origin": "console"
            },
            "message": "console error: error",
            "session_id": "0110cab4-7471-480e-aa4e-7ce039ced355",
            "status": "error",
            "view": {
              "referrer": "",
              "url": "https://datadoghq.dev/browser-sdk-test-playground"
            }
          },
          "tags": [
            "browser_sdk_version:3.6.13"
          ]
        }
        """)
        messageHandler?.userContentController(controller, didReceive: webLogMessage)

        messageHandler?.queue.sync {}
        let webRUMMessage = MockScriptMessage(body: """
        {
          "eventType": "view",
          "event": {
            "application": {
              "id": "xxx"
            },
            "date": 1635933113708,
            "service": "super",
            "session": {
              "id": "0110cab4-7471-480e-aa4e-7ce039ced355",
              "type": "user"
            },
            "type": "view",
            "view": {
              "action": {
                "count": 0
              },
              "cumulative_layout_shift": 0,
              "dom_complete": 152800000,
              "dom_content_loaded": 118300000,
              "dom_interactive": 116400000,
              "error": {
                "count": 0
              },
              "first_contentful_paint": 121300000,
              "id": "64308fd4-83f9-48cb-b3e1-1e91f6721230",
              "in_foreground_periods": [],
              "is_active": true,
              "largest_contentful_paint": 121299000,
              "load_event": 152800000,
              "loading_time": 152800000,
              "loading_type": "initial_load",
              "long_task": {
                "count": 0
              },
              "referrer": "",
              "resource": {
                "count": 3
              },
              "time_spent": 3120000000,
              "url": "http://localhost:8080/test.html"
            },
            "_dd": {
              "document_version": 2,
              "drift": 0,
              "format_version": 2,
              "session": {
                "plan": 2
              }
            }
          },
          "tags": [
            "browser_sdk_version:3.6.13"
          ]
        }
        """)
        messageHandler?.userContentController(controller, didReceive: webRUMMessage)
        waitForExpectations(timeout: 1)
    }
}

#endif
