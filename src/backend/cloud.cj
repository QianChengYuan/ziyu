package ziyu.backend

import audio4cj.pcm.AudioBuffer
import ziyu.frontend.DefaultFrontend
import ziyu.frontend.FrontendResult
import ziyu.frontend.TextFrontend

/* ============================================================================
 * CloudBackend —— 云端 TTS 后端（MVP2）
 *
 * 定位：核心库零网络依赖，通过「传输层依赖注入」把网络与解码隔离出去：
 *
 *   前端（归一化文本） → CloudBackend → CloudTransport(网络+解码) → PCM
 *
 *   - CloudTransport：抽象「发请求 + 解码音频」，实现方在独立模块接入
 *     stdx.net.http / http_lib / native curl，并负责 MP3/WAV → PCM 解码
 *   - CloudBackend：构造请求、调度传输层、声明 capabilities
 *   - LoopbackTransport：本地回环实现（无网络），用 LocalBackend 模拟云端，
 *     用于验证云端调度链路；真实接入请自行实现 CloudTransport
 *
 * 流式：synthesizeStream 直接透传传输层的 PCM 块流，实现「边下边播」。
 * ========================================================================== */

/// 云端合成请求（云端只接受文本 + 参数，不感知音素/韵律）
public struct CloudRequest {
    public let text: String // 归一化文本
    public let language: String // BCP-47
    public let voiceId: String // 云端音色 ID
    public let speed: Float32
    public let pitch: Float32
    public let volume: Float32

    public init(text: String, language: String, voiceId: String, speed: Float32, pitch: Float32, volume: Float32) {
        this.text = text
        this.language = language
        this.voiceId = voiceId
        this.speed = speed
        this.pitch = pitch
        this.volume = volume
    }
}

/// 云端传输抽象：发请求 + 解码音频 → PCM
///
/// 核心库不引入网络/解码依赖；实现方（如接入 stdx.net.http + audio4cj 解码）
/// 在独立模块提供，以隔离各云厂商的鉴权与编码差异。
public interface CloudTransport {
    /// 离线整段：返回解码后的 PCM
    func synthesize(request: CloudRequest): AudioBuffer
    /// 流式：返回 PCM 块流（边下边播）
    func synthesizeStream(request: CloudRequest): AudioStream
}

/// 云端 TTS 后端（传输层依赖注入）
public class CloudBackend <: TtsBackend {
    private let transport: CloudTransport
    private let voiceId: String
    private let language: String
    private let speed: Float32
    private let pitch: Float32
    private let volume: Float32
    private let sampleRate: Int64

    public init(
        transport!: CloudTransport,
        voiceId!: String = "zh-CN-Xiaoxiao",
        language!: String = "zh-CN",
        speed!: Float32 = 1.0,
        pitch!: Float32 = 1.0,
        volume!: Float32 = 1.0,
        sampleRate!: Int64 = 24000
    ) {
        this.transport = transport
        this.voiceId = voiceId
        this.language = language
        this.speed = speed
        this.pitch = pitch
        this.volume = volume
        this.sampleRate = sampleRate
    }

    private func buildRequest(input: FrontendResult): CloudRequest {
        CloudRequest(input.text, input.language, voiceId, speed, pitch, volume)
    }

    public func synthesize(input: FrontendResult): AudioBuffer {
        transport.synthesize(buildRequest(input))
    }

    public func synthesizeStream(input: FrontendResult): AudioStream {
        transport.synthesizeStream(buildRequest(input))
    }

    public func capabilities(): BackendCapability {
        BackendCapability(
            name: "cloud",
            languages: [language],
            sampleRate: sampleRate,
            channels: 1,
            streaming: true,
            offline: false,
            native: true
        )
    }
}

/// 本地回环传输：用 LocalBackend 合成模拟云端返回（无网络，验证云端调度链路）
///
/// 真实云端接入请实现 CloudTransport（发 HTTP 请求 + 解码返回音频）。
public class LoopbackTransport <: CloudTransport {
    private let local: LocalBackend
    private let frontend: TextFrontend

    public init(
        local!: LocalBackend = LocalBackend(),
        frontend!: TextFrontend = DefaultFrontend()
    ) {
        this.local = local
        this.frontend = frontend
    }

    public func synthesize(request: CloudRequest): AudioBuffer {
        // 模拟云端「只吃文本」：传输层内部再走一次前端
        local.synthesize(frontend.process(request.text, request.language))
    }

    public func synthesizeStream(request: CloudRequest): AudioStream {
        local.synthesizeStream(frontend.process(request.text, request.language))
    }
}
