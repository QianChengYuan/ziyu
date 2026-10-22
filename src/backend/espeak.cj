package ziyu.backend

import audio4cj.pcm.AudioBuffer
import std.collection.concurrent.ArrayBlockingQueue
import std.env.getTempDirectory
import std.fs.File
import std.process.execute
import ziyu.core.SynthesisStream
import ziyu.frontend.FrontendResult

/* ============================================================================
 * EspeakBackend —— espeak-ng 命令行引擎（跨平台，零 FFI）
 *
 * 通过 std.process 调用 espeak-ng 合成到 WAV，再读回解析为 PCM。
 *
 *   FrontendResult.text → espeak-ng → WAV → PCM(f32) → AudioBuffer
 *
 * 依赖：系统需安装 espeak-ng（含中文语音数据，如 `-v cmn`）。
 * 平台：Windows / Linux / macOS（有 espeak-ng 即可）。
 * 说明：进程调用而非 native 绑定，故 capabilities.native=false、offline=true。
 * ========================================================================== */

/// espeak-ng 后端
public class EspeakBackend <: TtsBackend {
    private let command: String
    private let voice: String
    private let speed: Int64 // 语速（词/分）
    private let pitch: Int64 // 音高 0-99
    private let amplitude: Int64 // 音量 0-200
    private let sampleRateHint: Int64

    public init(
        command!: String = "espeak-ng",
        voice!: String = "cmn", // cmn = 官话（普通话）
        speed!: Int64 = 150,
        pitch!: Int64 = 50,
        amplitude!: Int64 = 100,
        sampleRateHint!: Int64 = 22050
    ) {
        this.command = command
        this.voice = voice
        this.speed = speed
        this.pitch = pitch
        this.amplitude = amplitude
        this.sampleRateHint = sampleRateHint
    }

    /// 整段：一次调用 espeak-ng 合成
    public func synthesize(input: FrontendResult): AudioBuffer {
        espeakSynthesize(command, voice, speed, pitch, amplitude, input.text)
    }

    /// 流式：按句切分，逐段合成产出
    public func synthesizeStream(input: FrontendResult): AudioStream {
        let queue = ArrayBlockingQueue<?AudioBuffer>(4)
        let cmd = command
        let v = voice
        let s = speed
        let p = pitch
        let a = amplitude
        let segments = splitForSystem(input.text)
        spawn {
            =>
                for (seg in segments) {
                    queue.add(Some(espeakSynthesize(cmd, v, s, p, a, seg)))
                }
                queue.add(None)
        }
        AudioStream(SynthesisStream(queue))
    }

    public func capabilities(): BackendCapability {
        BackendCapability(
            name: "espeak-ng",
            languages: ["zh-CN", "en-US"],
            sampleRate: sampleRateHint,
            channels: 1,
            streaming: true,
            offline: true,
            native: false
        )
    }

    /// 检测 espeak-ng 命令是否可用（安装后为 true）
    public func isAvailable(): Bool {
        try {
            execute(command, ["--version"])
            true
        } catch (e: Exception) {
            false
        }
    }
}

/// 调 espeak-ng 合成到 WAV，再解析为 PCM(f32)
func espeakSynthesize(command: String, voice: String, speed: Int64, pitch: Int64, amplitude: Int64, text: String): AudioBuffer {
    let tmpDir = getTempDirectory().toString()
    let tag = uniqueTag()
    let txtPath = joinPath(tmpDir, "ziyu_espeak_${tag}.txt")
    let wavPath = joinPath(tmpDir, "ziyu_espeak_${tag}.wav")
    File.writeTo(txtPath, text.toArray()) // UTF-8
    execute(command, ["-v", voice, "-s", "${speed}", "-p", "${pitch}", "-a", "${amplitude}", "-w", wavPath, "-f",
        txtPath])
    let bytes = File.readFrom(wavPath)
    cleanup([txtPath, wavPath])
    let (pcm, sr, ch, bits) = parseWav(bytes)
    if (bits == 16 && pcm.size > 0) {
        pcm16ToBuffer(pcm, sr, ch)
    } else {
        AudioBuffer(sr, 1, Array<Float32>(0, repeat: 0.0))
    }
}
