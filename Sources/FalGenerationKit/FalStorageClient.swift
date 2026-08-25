// ABOUTME: Uploads a reference to FAL storage and returns the URL the provider issued for it.
// ABOUTME: Replaces a base64 data URI built in a SwiftUI view, which cost a third again per request.

import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum FalStorageError: LocalizedError, Equatable {
    case unsupportedContent
    /// The file could not be read at all.
    ///
    /// Distinct from `unsupportedContent`, which means the bytes were read and are not a picture.
    /// A user whose file has been moved or deleted needs to hear something different from a user
    /// who chose a document.
    case unreadableFile(String)
    case initiateFailed(diagnostic: String)
    case transferFailed(diagnostic: String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedContent:
            return "That file is not an image Superscale can send: PNG, JPEG, TIFF and HEIC are."
        case let .unreadableFile(name):
            return "That file could not be read: \(name)"
        case let .initiateFailed(diagnostic):
            return "The provider would not accept the image: \(diagnostic)"
        case let .transferFailed(diagnostic):
            return "The image could not be sent: \(diagnostic)"
        }
    }
}

/// Puts a reference where the provider can read it.
///
/// **It holds nothing between calls.** `FAL_REQUEST_REFERENCE.md` makes that a hard rule: uploaded
/// URLs expire at the provider's discretion, so a reference is uploaded afresh on every call that
/// uses it. The rule is expressed by there being nowhere to put a cached value rather than by
/// remembering not to write one — this is a `struct` with two immutable dependencies.
public struct FalStorageClient: Sendable {
    public static let productionBaseURL = URL(string: "https://rest.fal.ai")
        ?? URL(fileURLWithPath: "/")

    private let transport: any FalHTTPTransport
    private let baseURL: URL

    public init(
        transport: any FalHTTPTransport = URLSessionFalHTTPTransport(),
        baseURL: URL = FalStorageClient.productionBaseURL
    ) {
        self.transport = transport
        self.baseURL = baseURL
    }

    /// The image types Superscale accepts on import, and therefore the ones it will send.
    ///
    /// Guide 2.2 lists them. Anything else is refused *before* the upload, because the alternative
    /// spends bandwidth to learn what the file already said.
    static let supportedTypes: Set<String> = [
        UTType.png.identifier,
        UTType.jpeg.identifier,
        UTType.tiff.identifier,
        UTType.heic.identifier,
    ]

    /// The content type of `data`, read from the bytes.
    ///
    /// By content rather than by extension. `FAL_REQUEST_REFERENCE.md` records that validating by
    /// extension was the weaker of the two implementations it drew on, and a file's name is
    /// something a user can change by accident.
    static func contentType(of data: Data) -> String? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let identifier = CGImageSourceGetType(source) as String?,
            supportedTypes.contains(identifier)
        else { return nil }
        return identifier
    }

    /// Uploads the file at `fileURL` and returns the URL the provider issued.
    ///
    /// **Takes a location rather than bytes so that the read happens here.** The caller was
    /// `MainView.submitFilter`, which is `@MainActor`, so `Data(contentsOf:)` ran as synchronous
    /// disk I/O on the thread drawing the window — tens of milliseconds of frozen interface for a
    /// large picture, every time Apply was pressed. This type is `Sendable` and not main-actor
    /// bound, so the same read happens on the cooperative pool.
    ///
    /// **Read once, used twice.** The bytes are needed for the content-type sniff and again for the
    /// transfer. Reading for each would double the disk I/O this signature exists to move, and no
    /// test can observe it from outside — so the property is carried by this shape rather than by
    /// an assertion, and confirmed by code review.
    ///
    /// Nothing is sent before the read succeeds. An unreadable file throws with the reason and the
    /// provider is never contacted, so it cannot be left holding a URL with nothing behind it.
    public func upload(
        fileURL: URL, fileName: String, apiKey: String
    ) async throws -> URL {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw FalStorageError.unreadableFile(fileURL.lastPathComponent)
        }

        guard let contentType = Self.contentType(of: data) else {
            throw FalStorageError.unsupportedContent
        }

        let destination = try await initiate(
            fileName: fileName, contentType: contentType, apiKey: apiKey)
        try await put(data, to: destination.uploadURL, contentType: contentType)
        return destination.fileURL
    }

    private struct Destination {
        let uploadURL: URL
        let fileURL: URL
    }

    /// Asks the provider where to put the bytes.
    ///
    /// The destination comes from the provider rather than being composed locally, which is what
    /// makes the returned `file_url` the provider's own.
    private func initiate(
        fileName: String, contentType: String, apiKey: String
    ) async throws -> Destination {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent("storage/upload/initiate"),
            resolvingAgainstBaseURL: false
        ) else {
            throw FalStorageError.initiateFailed(diagnostic: "The upload address is invalid.")
        }
        components.queryItems = [URLQueryItem(name: "storage_type", value: "gcs")]
        guard let url = components.url else {
            throw FalStorageError.initiateFailed(diagnostic: "The upload address is invalid.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        // The secret lives only in the header, never in a body, a URL, a log or a stored record.
        request.setValue("Key \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["file_name": fileName, "content_type": contentType],
            options: [.sortedKeys])

        let response: FalHTTPResponse
        do {
            response = try await transport.send(request)
        } catch {
            throw FalStorageError.initiateFailed(
                diagnostic: FalDiagnosticRedactor.redact(
                    error.localizedDescription, secrets: [apiKey]))
        }

        guard (200..<300).contains(response.statusCode) else {
            throw FalStorageError.initiateFailed(
                diagnostic: FalDiagnosticRedactor.providerDiagnostic(
                    from: response.body, secrets: [apiKey]))
        }

        guard let object = try? JSONSerialization.jsonObject(with: response.body),
            let dictionary = object as? [String: Any],
            let uploadURL = (dictionary["upload_url"] as? String).flatMap(URL.init(string:)),
            let fileURL = (dictionary["file_url"] as? String).flatMap(URL.init(string:))
        else {
            throw FalStorageError.initiateFailed(
                diagnostic: "The provider's reply did not say where to put the image.")
        }

        return Destination(uploadURL: uploadURL, fileURL: fileURL)
    }

    private func put(_ data: Data, to url: URL, contentType: String) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        let response: FalHTTPResponse
        do {
            response = try await transport.send(request)
        } catch {
            // The upload URL is signed and carries no credential of ours, so there is nothing to
            // redact here — but nothing is assumed about the message either.
            throw FalStorageError.transferFailed(diagnostic: error.localizedDescription)
        }

        guard (200..<300).contains(response.statusCode) else {
            throw FalStorageError.transferFailed(
                diagnostic: FalDiagnosticRedactor.providerDiagnostic(
                    from: response.body, secrets: []))
        }
    }
}
