package ziyu.core

import audio4cj.pcm.AudioBuffer
import std.collection.concurrent.ArrayBlockingQueue

/* ============================================================================
 * 核心接口与数据类型
 *
 * 设计要点：
 *   - PCM 统一用 audio4cj.pcm.AudioBuffer（f32 交错 [-1,1]），与上游解码
 *     产物同形，合成结果可直接喂给 play4cj.core.PcmSink 播放
 *   - AudioSink 接口与 play4cj.core.PcmSink 同形，ziyu 自定义以避免核心库
 *     依赖 play4cj（play4cj 传递依赖 winsound4cj，属 Windows/native 侧）
 *   - SynthesisEngine 是合成引擎 SPI，MVP 用 SineSynthesizer 起步，
 *     后续替换为共振峰合成（FormantSynthesizer），均纯仓颉
 * ========================================================================== */

/// 音色性别
public enum VoiceGender {
    Male | Female | Neutral
}

/// 音色描述
public struct Voice {
    public let id: String          // 如 "zh-CN-Xiaoxiao"
    public let language: String    // BCP-47，如 "zh-CN"
    public let sampleRate: Int64   // 采样率（Hz）
    public let gender: VoiceGender
    public init(id: String, language: String, sampleRate: Int64, gender: VoiceGender) {
        this.id = id
        this.language = language
        this.sampleRate = sampleRate
        this.gender = gender
    }
}

/// 合成参数
public struct SynthesisOptions {
    public let speed: Float32      // 语速倍率，1.0 为默认
    public let pitch: Float32      // 基频倍率，1.0 为默认
    public let volume: Float32     // 0.0 ~ 1.0
    public init(speed: Float32, pitch: Float32, volume: Float32) {
        this.speed = speed
        this.pitch = pitch
        this.volume = volume
    }
    /// 默认参数
    public static func defaultOptions(): SynthesisOptions {
        SynthesisOptions(1.0, 1.0, 1.0)
    }
}

/// 合成请求
public struct SynthesisRequest {
    public let text: String
    public let voice: Voice
    public let options: SynthesisOptions
    public init(text: String, voice: Voice, options: SynthesisOptions) {
        this.text = text
        this.voice = voice
        this.options = options
    }
}

/// 音频汇接口（播放后端抽象）。
///
/// 与 play4cj.core.PcmSink 同形（onFormat/write/close），ziyu 自定义以使
/// 核心库不依赖 play4cj。使用方在调用侧写一个适配器即可桥接到
/// play4cj.winsound.WaveOutStreamSink（见 example 模块）。
public interface AudioSink {
    func onFormat(sampleRate: Int64, channels: Int64): Unit
    func write(chunk: AudioBuffer): Unit
    func close(): Unit
}

/// 合成引擎抽象（SPI）。实现者提供"文本 → AudioBuffer"的纯仓颉合成。
public interface SynthesisEngine {
    func synthesize(request: SynthesisRequest): AudioBuffer
    func listVoices(): Array<Voice>
    func engineName(): String

    /// 流式合成：逐块产出 AudioBuffer，None 表示结束。
    ///
    /// 默认实现：一次性合成整块后放入队列（非真流式，作为兜底）。
    /// FormantSynthesizer 覆写为 spawn 逐音素产块的真流式实现。
    func synthesizeStream(request: SynthesisRequest): SynthesisStream {
        let queue = ArrayBlockingQueue<?AudioBuffer>(2)
        let buf = synthesize(request)
        queue.add(Some(buf))
        queue.add(None)
        SynthesisStream(queue)
    }
}

/// 对外门面
public class TextToSpeech {
    private let engine: SynthesisEngine
    public init(engine: SynthesisEngine) { this.engine = engine }

    /// 合成文本为单个 AudioBuffer（适合短文本/离线导出）
    public func speak(text: String, voice: Voice,
        options!: SynthesisOptions = SynthesisOptions.defaultOptions()): AudioBuffer {
        engine.synthesize(SynthesisRequest(text, voice, options))
    }

    /// 流式合成：返回逐块产出的句柄（适合实时播放）
    public func speakStream(text: String, voice: Voice,
        options!: SynthesisOptions = SynthesisOptions.defaultOptions()): SynthesisStream {
        engine.synthesizeStream(SynthesisRequest(text, voice, options))
    }

    /// 可用音色
    public func voices(): Array<Voice> { engine.listVoices() }

    /// 引擎名
    public func engineName(): String { engine.engineName() }
}