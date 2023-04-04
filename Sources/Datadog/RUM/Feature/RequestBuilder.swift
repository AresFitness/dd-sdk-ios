/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// The RUM URL Request Builder for formatting and configuring the `URLRequest`
/// to upload RUM data.
internal struct RequestBuilder: FeatureRequestBuilder {
    /// The tracing intake.
    let customIntakeURL: URL?

    /// The RUM request body format.
    let format = DataFormat(prefix: "", suffix: "", separator: "\n")

    func request(for events: [Data], with context: DatadogContext) -> URLRequest {
        var tags = [
            "service:\(context.service)",
            "version:\(context.version)",
            "sdk_version:\(context.sdkVersion)",
            "env:\(context.env)",
        ]

        if let variant = context.variant {
            tags.append("variant:\(variant)")
        }

        let builder = URLRequestBuilder(
            url: url(with: context),
            queryItems: [
                .ddsource(source: context.source),
                .ddtags(tags: tags)
            ],
            headers: [
                .contentTypeHeader(contentType: .textPlainUTF8),
                .userAgentHeader(
                    appName: context.applicationName,
                    appVersion: context.version,
                    device: context.device
                ),
                .ddAPIKeyHeader(clientToken: context.clientToken),
                .ddEVPOriginHeader(source: context.ciAppOrigin ?? context.source),
                .ddEVPOriginVersionHeader(sdkVersion: context.sdkVersion),
                .ddRequestIDHeader(),
            ]
        )

        let data = format.format(events)
        return builder.uploadRequest(with: data)
    }

    func url(with context: DatadogContext) -> URL {
        customIntakeURL ?? context.site.endpoint.appendingPathComponent("api/v2/rum")
    }
}
