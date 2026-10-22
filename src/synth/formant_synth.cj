package ziyu.synth

import audio4cj.pcm.AudioBuffer
import std.collection.ArrayList
import std.collection.concurrent.ArrayBlockingQueue
import std.math.clamp
import std.math.cos
import ziyu.core.SynthesisEngine
import ziyu.core.SynthesisOptions
import ziyu.core.SynthesisRequest
import ziyu.core.SynthesisStream
import ziyu.core.Voice
import ziyu.core.VoiceGender
import ziyu.frontend.DefaultFrontend
import ziyu.frontend.TextFrontend

/* ============================================================================
 * FormantSynthesizer —— 共振峰规则合成器
 *
 * 离线：synthesize → 整段 AudioBuffer
 * 流式：synthesizeStream → spawn 合成线程逐音素产块 → ArrayBlockingQueue
 *
 * 链路：文本 → TextFrontend(音素序列) → 逐音素 pinyinToSegments(合成段,声调)
 *       → 逐段 [声门气流激励 → F1/F2/F3 并联滤波 → 唇辐射] → PCM 片段
 *
 * 声源：浊音段 voicedSource(phase)（Rosenberg 声门气流，双极性，-12dB/oct），
 *       清音段 NoiseSource 白噪声；输出端唇辐射 +6dB/oct → 净 -6dB/oct。
 * 滤波器：F1..F5 谐振器在整个合成过程中**复用**，段切换只更新系数不重置状态，
 *       唇辐射一阶差分状态亦跨音素继承 → 消除段落边界输出跳变。
 * 基频 F0：男 130Hz / 女 220Hz / 中性 165Hz，按声调（1-5）用 toneF0 调制，
 *          并跨音节平滑，禁止直接跳变。
 * 输出：峰值归一化到 -3dBFS；音节时长 ±10% 抖动；首尾 3ms 余弦 ramp。
 *
 * 纯仓颉：Float64 运算 + std.math.clamp + std.collection.concurrent，零 FFI。
 * ========================================================================== */

/// 共振峰规则合成器
public class FormantSynthesizer <: SynthesisEngine {
    private let pipeline: TextFrontend
    private let defaultVoice: Voice
    private let noise: NoiseSource

    /// - param pipeline: 文本前端（默认 DefaultFrontend）
    /// - param voice: 默认音色（22050 Hz 单声道中性）
    public init(
        pipeline!: TextFrontend = DefaultFrontend(),
        voice!: Voice = Voice("zh-CN-formant", "zh-CN", 22050, VoiceGender.Neutral)
    ) {
        this.pipeline = pipeline
        this.defaultVoice = voice
        this.noise = NoiseSource()
    }

    // ── SynthesisEngine 实现：文本 → 前端 → 音素 → 合成 ──

    public func synthesize(request: SynthesisRequest): AudioBuffer {
        let frontend = pipeline.process(request.text, request.voice.language)
        synthesizePhonemes(frontend.symbols(), request.voice, request.options)
    }

    /// 流式合成：spawn 合成线程逐音素产块，通过阻塞队列传递
    public func synthesizeStream(request: SynthesisRequest): SynthesisStream {
        let frontend = pipeline.process(request.text, request.voice.language)
        streamPhonemes(frontend.symbols(), request.voice, request.options)
    }

    // ── 按音素序列合成（供 backend 消费前端产出） ──

    /// 直接按音素序列合成整段 PCM（峰值归一化到 -3dBFS）
    public func synthesizePhonemes(phonemes: Array<String>, voice: Voice, options: SynthesisOptions): AudioBuffer {
        let sampleRate = voice.sampleRate
        let fs = Float64(sampleRate)
        if (phonemes.size == 0) {
            return AudioBuffer(sampleRate, 1, Array<Float32>(0, repeat: 0.0))
        }
        let baseF0 = baseFreq(voice.gender) * Float64(options.pitch)
        let speed = Float64(options.speed)
        let volume = Float64(options.volume)
        let interFrames = Int64(60.0 * fs / 1000.0 / speed)
        // 滤波器与唇辐射状态跨音素复用（整个合成中只创建一次）
        let filters = newFilters(fs)
        let all = ArrayList<Float32>()
        var phase = 0.0
        var lastF0 = 0.0
        var yPrev = 0.0
        for (pi in 0..phonemes.size) {
            let (chunk, newPhase, newF0, newYPrev) = synthOnePhoneme(phonemes[pi], fs, baseF0, speed, volume, noise,
                interFrames, phase, lastF0, filters, yPrev)
            phase = newPhase
            lastF0 = newF0
            yPrev = newYPrev
            for (s in chunk) {
                all.add(s)
            }
        }
        AudioBuffer(sampleRate, 1, normalizePeak(dcBlock(all.toArray()), 0.7079))
    }

    /// 按音素序列流式合成：spawn 合成线程逐音素产块
    public func streamPhonemes(phonemes: Array<String>, voice: Voice, options: SynthesisOptions): SynthesisStream {
        let queue = ArrayBlockingQueue<?AudioBuffer>(4)
        let sampleRate = voice.sampleRate
        let fs = Float64(sampleRate)
        // 捕获到局部变量，避免闭包直接捕获 this
        let nz = noise
        let gender = voice.gender
        let pitch = Float64(options.pitch)
        let speed = Float64(options.speed)
        let volume = Float64(options.volume)
        spawn {
            =>
                let baseF0 = baseFreq(gender) * pitch
                let interFrames = Int64(60.0 * fs / 1000.0 / speed)
                let filters = newFilters(fs)
                var phase = 0.0
                var lastF0 = 0.0
                var yPrev = 0.0
                for (pi in 0..phonemes.size) {
                    let (chunk, newPhase, newF0, newYPrev) = synthOnePhoneme(phonemes[pi], fs, baseF0, speed, volume,
                        nz, interFrames, phase, lastF0, filters, yPrev)
                    phase = newPhase
                    lastF0 = newF0
                    yPrev = newYPrev
                    queue.add(Some(AudioBuffer(sampleRate, 1, normalizePeak(dcBlock(chunk.toArray()), 0.7079))))
                }
                queue.add(None)
        }
        SynthesisStream(queue)
    }

    public func listVoices(): Array<Voice> {
        Array<Voice>(1, {_ => defaultVoice})
    }

    public func engineName(): String {
        "formant"
    }
}

/// 创建并联谐振器组（F1..F5，初始系数占位，段切换时 setCoefficients 更新）
func newFilters(fs: Float64): Array<FormantFilter> {
    Array<FormantFilter>(5, {_ => FormantFilter(500.0, 80.0, fs)})
}

/// 合成单个音素（含段间滤波与尾部停顿）
///
/// 返回 (样本列表, 新相位, 末尾 F0, 末尾唇辐射状态)。
/// 滤波器 `filters` 与唇辐射状态 `yPrevIn` 从上一音素继承，段切换仅
/// setCoefficients 更新系数、不重置内部状态，消除段落边界跳变。
func synthOnePhoneme(phoneme: String, fs: Float64, baseF0: Float64, speed: Float64, volume: Float64,
    noise: NoiseSource, interFrames: Int64, phaseIn: Float64, lastF0In: Float64,
    filters: Array<FormantFilter>, yPrevIn: Float64): (ArrayList<Float32>, Float64, Float64, Float64) {
    var phase = phaseIn
    var lastF0 = lastF0In
    var voicedCount: Int64 = 0
    var yPrev = yPrevIn
    let twoPi = 2.0 * 3.141592653589793
    let smoothFrames = Int64(30.0 * fs / 1000.0)
    let samples = ArrayList<Float32>()
    let (segments, tone) = pinyinToSegments(phoneme)
    let zeroF32 = Float32(0.0)
    // 预计算韵母总帧数，用于声调轮廓跨段连续变化（不复韵母每段重置）
    var totalVowelFrames: Int64 = 0
    for (preIdx in 0..segments.size) {
        if (!segments[preIdx].isConsonant) {
            totalVowelFrames += Int64(segments[preIdx].formants.durationMs * fs / 1000.0 / speed)
        }
    }
    var vowelFrameElapsed: Int64 = 0
    for (segIdx in 0..segments.size) {
        let seg = segments[segIdx]
        if (seg.formants.durationMs <= 0.0) {
            continue
        }
        // 时长 ±10% 抖动（确定性，降低机械感）
        let jitter = 0.9 + 0.2 * durJitter(phoneme, segIdx)
        let nFrames = Int64(seg.formants.durationMs * fs / 1000.0 / speed * jitter)
        if (nFrames <= 0) {
            continue
        }
        // 复用同一组谐振器：仅更新系数，保留内部状态（避免段边界跳变）
        filters[0].setCoefficients(seg.formants.f1, seg.formants.b1, fs)
        filters[1].setCoefficients(seg.formants.f2, seg.formants.b2, fs)
        filters[2].setCoefficients(seg.formants.f3, seg.formants.b3, fs)
        filters[3].setCoefficients(3500.0, 200.0, fs)   // F4 固定
        filters[4].setCoefficients(6000.0, 300.0, fs)   // F5 固定
        // F2 频率相关三档权重
        let f2w = if (seg.formants.f2 < 1000.0) {
            1.5
        } else if (seg.formants.f2 < 2000.0) {
            3.0
        } else {
            2.0
        }
        // 振幅包络
        let isConsonant = seg.isConsonant
        let isFirstVowel = (!isConsonant && (segIdx == 0 || (segIdx == 1 && segments[0].isConsonant)))
        let segAmp = if (isConsonant) {
            0.6
        } else {
            1.0
        }
        let attackRatio = if (isConsonant) {
            0.2
        } else if (isFirstVowel) {
            0.1
        } else {
            0.0
        }
        let releaseRatio = if (isConsonant) {
            0.3
        } else {
            0.0
        }
        for (i in 0..nFrames) {
            let src = if (seg.isNoise) {
                noise.next() * 0.3
            } else {
                voicedSource(phase)
            }
            if (!seg.isNoise) {
                let toneProgress = if (totalVowelFrames > 0) {
                    Float64(vowelFrameElapsed + i) / Float64(totalVowelFrames)
                } else {
                    Float64(i) / Float64(nFrames)
                }
                let target = toneF0(baseF0, tone, toneProgress)
                // 跨音节平滑：音节起始 ~30ms 从上一末尾 F0 过渡到目标
                var curF0 = target
                if (smoothFrames > 0 && lastF0 > 0.0 && voicedCount < smoothFrames) {
                    let w = Float64(voicedCount) / Float64(smoothFrames)
                    curF0 = lastF0 + (target - lastF0) * w
                }
                lastF0 = curF0
                voicedCount += 1
                phase += twoPi * curF0 / fs
                if (phase > twoPi) {
                    phase -= twoPi
                }
            }
            // 并联滤波加权：F1 为主（元音身份），F2 频率相关，F3/F4/F5 补高频
            let y = filters[0].process(src) * 1.0 + filters[1].process(src) * f2w + filters[2].process(src) * 0.25 +
                filters[3].process(src) * 0.4 + filters[4].process(src) * 0.15
            // 唇辐射特性：一阶差分预加重 +6dB/oct；状态跨音素继承
            let yRad = y - 1.0 * yPrev
            yPrev = y
            // 振幅包络：渐入→平台→渐出
            let prog = Float64(i) / Float64(nFrames)
            var env = 1.0
            if (attackRatio > 0.0 && prog < attackRatio) {
                env = prog / attackRatio
            } else if (releaseRatio > 0.0 && prog > 1.0 - releaseRatio) {
                env = (1.0 - prog) / releaseRatio
            }
            let out = clamp(yRad * 1.1 * volume * segAmp * env, -1.0, 1.0)
            samples.add(Float32(out))
        }
        // 累计韵母帧数
        if (!isConsonant) {
            vowelFrameElapsed += nFrames
        }
        // 声母→韵母过渡静音（15ms）
        if (isConsonant) {
            let transFrames = Int64(15.0 * fs / 1000.0 / speed)
            for (j in 0..transFrames) {
                samples.add(zeroF32)
            }
        }
    }
    // 音素间短停顿
    for (j in 0..interFrames) {
        samples.add(zeroF32)
    }
    // 音节首尾余弦淡入淡出（3ms：调幅频率 ~333Hz，高于基频，不被感知）
    applyRamp(samples, Int64(3.0 * fs / 1000.0))
    (samples, phase, lastF0, yPrev)
}

/// 声调 F0 轮廓（相对基频倍数，按男声经验值）
///
/// - 一声 1.00→1.00；二声 0.85→1.20；三声 0.75→0.65→1.00；四声 1.25→0.65
func toneF0(baseF0: Float64, tone: Int64, progress: Float64): Float64 {
    match (tone) {
        case 1 =>
            // 阴平：平调 1.00→1.00
            baseF0
        case 2 =>
            // 阳平：升调 0.85→1.20
            baseF0 * (0.85 + 0.35 * progress)
        case 3 =>
            // 上声：降升调 0.75→0.65→1.00
            if (progress < 0.5) {
                baseF0 * (0.75 - 0.10 * (progress / 0.5))
            } else {
                baseF0 * (0.65 + 0.35 * ((progress - 0.5) / 0.5))
            }
        case 4 =>
            // 去声：降调 1.25→0.65
            baseF0 * (1.25 - 0.60 * progress)
        case _ =>
            // 轻声/未知：低平调
            baseF0 * 0.75
    }
}

/// 按音色性别取基频 F0（Hz）——男 130 / 女 220 / 中性 165
func baseFreq(gender: VoiceGender): Float64 {
    match (gender) {
        case Male => 130.0
        case Female => 220.0
        case Neutral => 165.0
    }
}

/// 时长抖动系数 [0,1)（确定性：按音素与段序号散列）
func durJitter(phoneme: String, segIdx: Int64): Float64 {
    var h: Int64 = 0
    for (c in phoneme.toRuneArray()) {
        h = (h * 131 + Int64(UInt32(c))) % 1000003
    }
    h = (h * 31 + segIdx) % 1000003
    Float64(h) / 1000003.0
}

/// 峰值归一化到目标幅度（默认 -3dBFS ≈ 0.7079）
func normalizePeak(samples: Array<Float32>, target: Float64): Array<Float32> {
    var peak = 0.0
    for (s in samples) {
        let a = Float64(if (s < 0.0) { -s } else { s })
        if (a > peak) {
            peak = a
        }
    }
    if (peak <= 0.000001) {
        return samples
    }
    let gain = Float32(target / peak)
    Array<Float32>(samples.size, { i => samples[i] * gain })
}

/// 一阶 DC blocker（截止 ~20Hz）：y[n] = x[n] - x[n-1] + 0.995·y[n-1]
func dcBlock(samples: Array<Float32>): Array<Float32> {
    let out = ArrayList<Float32>(samples.size)
    var xPrev = 0.0
    var yPrev = 0.0
    for (s in samples) {
        let x = Float64(s)
        let y = x - xPrev + 0.995 * yPrev
        xPrev = x
        yPrev = y
        out.add(Float32(y))
    }
    out.toArray()
}

/// 首尾余弦淡入淡出（各 rampFrames 个样本）
func applyRamp(samples: ArrayList<Float32>, rampFrames: Int64): Unit {
    let n = samples.size
    if (rampFrames <= 0 || n <= 2 * rampFrames) {
        return
    }
    for (i in 0..rampFrames) {
        let w = Float32(0.5 - 0.5 * cos(3.141592653589793 * Float64(i) / Float64(rampFrames)))
        samples[i] = samples[i] * w
        samples[n - 1 - i] = samples[n - 1 - i] * w
    }
}