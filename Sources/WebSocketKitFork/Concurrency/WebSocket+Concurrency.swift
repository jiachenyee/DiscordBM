#if compiler(>=5.5) && canImport(_Concurrency)
import NIOCore
import NIOWebSocket
import Foundation

@available(macOS 12, iOS 15, watchOS 8, tvOS 15, *)
extension WebSocket {
    public func send<S>(_ text: S) async throws
        where S: Collection, S.Element == Character
    {
        let promise = eventLoop.makePromise(of: Void.self)
        send(text, promise: promise)
        return try await promise.futureResult.get()
    }

    public func send(_ binary: [UInt8]) async throws {
        let promise = eventLoop.makePromise(of: Void.self)
        send(binary, promise: promise)
        return try await promise.futureResult.get()
    }

    public func sendPing() async throws {
        let promise = eventLoop.makePromise(of: Void.self)
        sendPing(promise: promise)
        return try await promise.futureResult.get()
    }

    public func send<Data>(
        raw data: Data,
        opcode: WebSocketOpcode,
        fin: Bool = true
    ) async throws
        where Data: DataProtocol
    {
        let promise = eventLoop.makePromise(of: Void.self)
        send(raw: data, opcode: opcode, fin: fin, promise: promise)
        return try await promise.futureResult.get()
    }

    public func close(code: WebSocketErrorCode = .goingAway) async throws {
        try await close(code: code).get()
    }

    public func onText(_ callback: @escaping (WebSocket, String) async -> ()) {
        onText { socket, text in
            Task {
                await callback(socket, text)
            }
        }
    }

    public func onBinary(_ callback: @escaping (WebSocket, ByteBuffer) async -> ()) {
        onBinary { socket, binary in
            Task {
                await callback(socket, binary)
            }
        }
    }

    public func onPong(_ callback: @escaping (WebSocket) async -> ()) {
        onPong { socket in
            Task {
                await callback(socket)
            }
        }
    }

    public func onPing(_ callback: @escaping (WebSocket) async -> ()) {
        onPing { socket in
            Task {
                await callback(socket)
            }
        }
    }

    public static func connect(
        to url: String,
        headers: HTTPHeaders = [:],
        configuration: WebSocketClient.Configuration = .init(),
        on eventLoopGroup: EventLoopGroup,
        onUpgrade: @Sendable @escaping (WebSocket) async -> ()
    ) async throws {
        return try await self.connect(
            to: url,
            headers: headers,
            configuration: configuration,
            on: eventLoopGroup,
            onUpgrade: { ws in
                Task {
                    await onUpgrade(ws)
                }
            }
        ).get()
    }

    public static func connect(
        to url: URL,
        headers: HTTPHeaders = [:],
        configuration: WebSocketClient.Configuration = .init(),
        on eventLoopGroup: EventLoopGroup,
        onUpgrade: @Sendable @escaping (WebSocket) async -> ()
    ) async throws {
        return try await self.connect(
            to: url,
            headers: headers,
            configuration: configuration,
            on: eventLoopGroup,
            onUpgrade: { ws in
                Task {
                    await onUpgrade(ws)
                }
            }
        ).get()
    }

    public static func connect(
        scheme: String = "ws",
        host: String,
        port: Int = 80,
        path: String = "/",
        query: String? = nil,
        headers: HTTPHeaders = [:],
        configuration: WebSocketClient.Configuration = .init(),
        on eventLoopGroup: EventLoopGroup,
        onUpgrade: @Sendable @escaping (WebSocket) async -> ()
    ) async throws {
        return try await self.connect(
            scheme: scheme,
            host: host,
            port: port,
            path: path,
            query: query,
            headers: headers,
            configuration: configuration,
            on: eventLoopGroup,
            onUpgrade: { ws in
                Task {
                    await onUpgrade(ws)
                }
            }
        ).get()
    }
}

#endif
