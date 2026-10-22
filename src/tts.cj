package ziyu

import audio4cj.pcm.AudioBuffer
import ziyu.backend.AudioStream
import ziyu.backend.BackendCapability
import ziyu.backend.LocalBackend
import ziyu.backend.TtsBackend
import ziyu.frontend.DefaultFrontend
import ziyu.frontend.TextFrontend

/* ============================================================================
 * Tts —— 统一调度层（用户 API）
 *
 * 定位：不做合成引擎，做「中文文本前端 + 统一调度层」。
 *   speak(text)        前端(归一化+音素+韵律) → backend → 整段 PCM
 *   speakStream(text)  前端 → backend → 逐块 PCM
 *
 * backend 可替换：LocalBackend（纯仓颉共振峰）/ 后续 SystemBackend / CloudBackend。
 * 核心库保持纯仓颉零 FFI，native 能力由各 backend 在独立模块接入。
 * ========================================================================== */

/// TTS 统一门面
public class Tts {
    private let frontend: TextFrontend
    private let backend: TtsBackend

    public init(
        frontend!: TextFrontend = DefaultFrontend(),
        backend!: TtsBackend = LocalBackend()
    ) {
        this.frontend = frontend
        this.backend = backend
    }

    /// 合成整段 PCM（短文本/离线导出）
    public func speak(text: String, language!: String = "zh-CN"): AudioBuffer {
        backend.synthesize(frontend.process(text, language))
    }

    /// 流式合成：逐块产出 PCM（实时播放）
    public func speakStream(text: String, language!: String = "zh-CN"): AudioStream {
        backend.synthesizeStream(frontend.process(text, language))
    }

    /// 当前 backend 能力
    public func capabilities(): BackendCapability {
        backend.capabilities()
    }
}
