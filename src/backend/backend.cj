package ziyu.backend

import audio4cj.pcm.AudioBuffer
import ziyu.core.SynthesisStream
import ziyu.frontend.FrontendResult

/* ============================================================================
 * Backend 抽象层（接口先行）
 *
 * 定位：不做合成引擎，只定义统一调度接口，让多种引擎（本地/系统/云端）
 * 各自实现。前端产出 FrontendResult 作为唯一输入契约。
 *
 *   前端（音素 + 韵律） → TtsBackend → PCM 流 → 音频输出层
 *
 * 核心库保持纯仓颉零 FFI：本层只声明契约，native 能力由各实现方
 * 在独立模块接入（本层不含 foreign/unsafe/@C）。
 * ========================================================================== */

/// 后端能力声明
public struct BackendCapability {
    public let name: String // 后端名，如 "local-formant"
    public let languages: Array<String> // 支持语言
    public let sampleRate: Int64 // 输出采样率（Hz）
    public let channels: Int64 // 输出声道数
    public let streaming: Bool // 是否支持流式合成
    public let offline: Bool // 是否离线本地
    public let native: Bool // 是否依赖 native/FFI
    public init(name!: String, languages!: Array<String>, sampleRate!: Int64, channels!: Int64, streaming!: Bool,
        offline!: Bool, native!: Bool) {
        this.name = name
        this.languages = languages
        this.sampleRate = sampleRate
        this.channels = channels
        this.streaming = streaming
        this.offline = offline
        this.native = native
    }
}

/// 音频流：逐块产出 PCM（backend 输出抽象）
///
/// 复用 ziyu.core.SynthesisStream（阻塞队列），对 backend 层暴露稳定的
/// 输出契约，便于后续在此之后接入重采样/格式归一环节。
public class AudioStream {
    private let inner: SynthesisStream
    public init(inner: SynthesisStream) {
        this.inner = inner
    }
    /// 阻塞取下一块；None 表示结束
    public func nextChunk(): ?AudioBuffer {
        inner.nextChunk()
    }
    /// 非阻塞尝试取
    public func tryNextChunk(): Option<?AudioBuffer> {
        inner.tryNextChunk()
    }
}

/// TTS 后端抽象：输入前端产出，输出 PCM
public interface TtsBackend {
    /// 离线整段合成
    func synthesize(input: FrontendResult): AudioBuffer
    /// 流式合成：逐块产出 PCM
    func synthesizeStream(input: FrontendResult): AudioStream
    /// 后端能力
    func capabilities(): BackendCapability
}
