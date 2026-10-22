package ziyu.backend

import audio4cj.pcm.AudioBuffer
import ziyu.core.SynthesisOptions
import ziyu.core.Voice
import ziyu.core.VoiceGender
import ziyu.frontend.FrontendResult
import ziyu.synth.FormantSynthesizer

/* ============================================================================
 * LocalBackend —— 本地纯仓颉 backend（包装共振峰合成引擎）
 *
 * 复用已完成的共振峰规则合成成果，按后端接口暴露：
 *   前端音素序列 → FormantSynthesizer → PCM
 * 纯仓颉、离线、零 FFI。
 * ========================================================================== */

/// 本地共振峰 backend
public class LocalBackend <: TtsBackend {
    private let synth: FormantSynthesizer
    private let voice: Voice
    private let options: SynthesisOptions

    public init(
        synth!: FormantSynthesizer = FormantSynthesizer(),
        voice!: Voice = Voice("zh-CN-local", "zh-CN", 22050, VoiceGender.Neutral),
        options!: SynthesisOptions = SynthesisOptions.defaultOptions()
    ) {
        this.synth = synth
        this.voice = voice
        this.options = options
    }

    public func synthesize(input: FrontendResult): AudioBuffer {
        synth.synthesizePhonemes(input.symbols(), voice, options)
    }

    public func synthesizeStream(input: FrontendResult): AudioStream {
        AudioStream(synth.streamPhonemes(input.symbols(), voice, options))
    }

    public func capabilities(): BackendCapability {
        BackendCapability(
            name: "local-formant",
            languages: ["zh-CN"],
            sampleRate: voice.sampleRate,
            channels: 1,
            streaming: true,
            offline: true,
            native: false
        )
    }
}
