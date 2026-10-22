package ziyu.synth

import audio4cj.pcm.AudioBuffer
import std.math.sin
import ziyu.core.SynthesisEngine
import ziyu.core.SynthesisRequest
import ziyu.core.Voice
import ziyu.core.VoiceGender

/* ============================================================================
 * SineSynthesizer —— MVP 起步合成器
 *
 * 把文本的每个 UTF-8 字节映射到一个正弦音调，生成可听的单声道 PCM。
 * 这不是最终语音，而是验证"文本 → AudioBuffer → WAV"纯仓颉链路的最小可运行
 * 实现；后续迭代将由 FormantSynthesizer（共振峰合成）替换，接口不变。
 *
 * 纯仓颉：仅用 std.math.sin 与 Float32 数组运算，零 FFI。
 * ========================================================================== */

/// MVP 正弦合成器
public class SineSynthesizer <: SynthesisEngine {
    private let voice: Voice

    /// - param voice: 默认音色（22050 Hz 单声道）
    public init(voice!: Voice = Voice("zh-CN-default", "zh-CN", 22050, VoiceGender.Neutral)) {
        this.voice = voice
    }

    public func synthesize(request: SynthesisRequest): AudioBuffer {
        let sampleRate = request.voice.sampleRate
        let bytes = request.text.toArray()   // UTF-8 字节序列
        let n = bytes.size
        // 每字节 120ms，speed 倍率调节时长
        let framesPerByte = Int64(Float64(sampleRate) * 0.12 / Float64(request.options.speed))
        if (framesPerByte <= 0 || n <= 0) {
            return AudioBuffer(sampleRate, 1, Array<Float32>(0, repeat: 0.0))
        }
        let totalFrames = framesPerByte * n
        let samples = Array<Float32>(totalFrames, repeat: 0.0)
        // 基频随字节值变化（110-830Hz），pitch 倍率调节
        let twoPi = 2.0 * 3.141592653589793
        var idx: Int64 = 0
        for (bi in 0..n) {
            let freq = (110.0 + Float64(Int64(bytes[bi]) % 12) * 60.0) * Float64(request.options.pitch)
            let phaseStep = twoPi * freq / Float64(sampleRate)
            for (i in 0..framesPerByte) {
                let v = sin(Float64(i) * phaseStep) * 0.25 * Float64(request.options.volume)
                samples[idx] = Float32(v)
                idx += 1
            }
        }
        AudioBuffer(sampleRate, 1, samples)
    }

    public func listVoices(): Array<Voice> {
        Array<Voice>(1, { _ => voice })
    }

    public func engineName(): String {
        "sine-mvp"
    }
}