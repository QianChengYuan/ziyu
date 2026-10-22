package ziyu.backend

import audio4cj.pcm.AudioBuffer
import std.collection.ArrayList
import std.collection.concurrent.ArrayBlockingQueue
import std.env.getTempDirectory
import std.fs.File
import std.fs.remove
import std.process.execute
import std.random.Random
import std.time.DateTime
import ziyu.core.SynthesisStream
import ziyu.frontend.FrontendResult

/* ============================================================================
 * SystemBackend —— 系统 TTS 后端（Windows SAPI，进程调用）
 *
 * 调用操作系统内置语音合成，**零 FFI**：用 std.process 运行 PowerShell 的
 * System.Speech，将文本合成到 WAV，再读回解析为 PCM。
 *
 *   FrontendResult.text → PowerShell / System.Speech → WAV → PCM(f32) → AudioBuffer
 *
 * 平台：Windows（System.Speech 自带；中文需已装中文语音，如
 *       "Microsoft Huihui Desktop"）。
 * 说明：属于「进程调用」而非 native 绑定，故 capabilities.native=false、offline=true。
 * ========================================================================== */

/// 系统 TTS 后端（Windows SAPI）
public class SystemBackend <: TtsBackend {
    private let voiceName: String
    private let powershell: String
    private let sampleRateHint: Int64

    public init(
        voiceName!: String = "Microsoft Huihui Desktop",
        powershell!: String = "powershell",
        sampleRateHint!: Int64 = 16000
    ) {
        this.voiceName = voiceName
        this.powershell = powershell
        this.sampleRateHint = sampleRateHint
    }

    /// 整段：一次调用 SAPI 合成
    public func synthesize(input: FrontendResult): AudioBuffer {
        sapiSynthesize(powershell, voiceName, input.text)
    }

    /// 流式：按句切分，逐段合成产出（边合成边播）
    public func synthesizeStream(input: FrontendResult): AudioStream {
        let queue = ArrayBlockingQueue<?AudioBuffer>(4)
        let ps = powershell
        let vn = voiceName
        let segments = splitForSystem(input.text)
        spawn {
            =>
                for (seg in segments) {
                    queue.add(Some(sapiSynthesize(ps, vn, seg)))
                }
                queue.add(None)
        }
        AudioStream(SynthesisStream(queue))
    }

    public func capabilities(): BackendCapability {
        BackendCapability(
            name: "system-sapi",
            languages: ["zh-CN", "en-US"],
            sampleRate: sampleRateHint,
            channels: 1,
            streaming: true,
            offline: true,
            native: false
        )
    }
}

// ── SAPI 调用 ──

/// 调 PowerShell System.Speech 合成到 WAV，再解析为 PCM(f32)
func sapiSynthesize(powershell: String, voiceName: String, text: String): AudioBuffer {
    let tmpDir = getTempDirectory().toString()
    let tag = uniqueTag()
    let txtPath = joinPath(tmpDir, "ziyu_sapi_${tag}.txt")
    let wavPath = joinPath(tmpDir, "ziyu_sapi_${tag}.wav")
    File.writeTo(txtPath, text.toArray()) // UTF-8
    execute(powershell, ["-NoProfile", "-NonInteractive", "-Command", sapiScript(voiceName, txtPath, wavPath)])
    let wavBytes = File.readFrom(wavPath)
    cleanup([txtPath, wavPath])
    let (pcm, sr, ch, bits) = parseWav(wavBytes)
    if (bits == 16 && pcm.size > 0) {
        pcm16ToBuffer(pcm, sr, ch)
    } else {
        AudioBuffer(sr, 1, Array<Float32>(0, repeat: 0.0))
    }
}

/// 构造 PowerShell 合成脚本（单引号字面量，避免转义问题）
func sapiScript(voiceName: String, txtPath: String, wavPath: String): String {
    "Add-Type -AssemblyName System.Speech; " + "$s = New-Object System.Speech.Synthesis.SpeechSynthesizer; " +
        "try { $s.SelectVoice('" + voiceName + "') } catch {}; " + "$t = [System.IO.File]::ReadAllText('" + txtPath +
        "', [System.Text.Encoding]::UTF8); " + "$s.SetOutputToWaveFile('" + wavPath + "'); " + "$s.Speak($t); " +
        "$s.Dispose()"
}

/// 清理临时文件
func cleanup(paths: Array<String>): Unit {
    for (p in paths) {
        try {
            remove(p)
        } catch (e: Exception) {
            () // 清理失败不影响合成结果
        }
    }
}

// ── WAV 解析（RIFF） ──

/// 解析 WAV：返回 (PCM 字节, 采样率, 声道, 位深)
func parseWav(b: Array<Byte>): (Array<Byte>, Int64, Int64, Int64) {
    var sampleRate: Int64 = 16000
    var channels: Int64 = 1
    var bits: Int64 = 16
    if (b.size < 44) {
        return (Array<Byte>(0, repeat: 0), sampleRate, channels, bits)
    }
    var offset: Int64 = 12
    while (offset + 8 <= b.size) {
        let off = offset
        let id = String.fromUtf8(Array<Byte>(4, {i => b[off + i]}))
        let size = le32(b, offset + 4)
        if (id == "fmt " && offset + 8 + 16 <= b.size) {
            channels = le16(b, offset + 10)
            sampleRate = le32(b, offset + 12)
            bits = le16(b, offset + 22)
        } else if (id == "data") {
            let start = offset + 8
            var end = start + size
            if (end > b.size) {
                end = b.size
            }
            let pcm = Array<Byte>(end - start, {i => b[start + i]})
            return (pcm, sampleRate, channels, bits)
        }
        offset += 8 + size + (size % 2)
    }
    (Array<Byte>(0, repeat: 0), sampleRate, channels, bits)
}

/// 小端 16 位
func le16(b: Array<Byte>, off: Int64): Int64 {
    Int64(b[off]) | (Int64(b[off + 1]) << 8)
}

/// 小端 32 位
func le32(b: Array<Byte>, off: Int64): Int64 {
    Int64(b[off]) | (Int64(b[off + 1]) << 8) | (Int64(b[off + 2]) << 16) | (Int64(b[off + 3]) << 24)
}

/// PCM16（小端）→ AudioBuffer(f32)
func pcm16ToBuffer(pcm: Array<Byte>, sampleRate: Int64, channels: Int64): AudioBuffer {
    let out = ArrayList<Float32>(pcm.size / 2)
    var i: Int64 = 0
    while (i + 1 < pcm.size) {
        let lo = Int64(pcm[i])
        let hi = Int64(pcm[i + 1])
        var v = lo | (hi << 8)
        if (v >= 32768) {
            v -= 65536
        }
        out.add(Float32(Float64(v) / 32768.0))
        i += 2
    }
    AudioBuffer(sampleRate, if (channels <= 0) {
        1
    } else {
        channels
    }, out.toArray())
}

// ── 辅助 ──

/// 拼接目录与文件名（保留目录已有分隔符）
func joinPath(dir: String, name: String): String {
    if (dir.size == 0) {
        return name
    }
    let runes = dir.toRuneArray()
    let last = runes[runes.size - 1]
    if (last == r'\\' || last == r'/') {
        "${dir}${name}"
    } else {
        "${dir}\\${name}"
    }
}

/// 唯一标签
func uniqueTag(): String {
    let ts = DateTime.nowUTC().toUnixTimeStamp().toSeconds()
    let r = Random(UInt64(ts)).nextUInt64()
    "${ts}_${r}"
}

/// 按句读标点切分（长文本分段合成）
func splitForSystem(text: String): Array<String> {
    let out = ArrayList<String>()
    let cur = ArrayList<Rune>()
    for (r in text.toRuneArray()) {
        cur.add(r)
        if (isSystemPunct(r) && cur.size >= 12) {
            out.add(String(cur.toArray()))
            cur.clear()
        }
    }
    if (cur.size > 0) {
        out.add(String(cur.toArray()))
    }
    if (out.size == 0) {
        out.add(text)
    }
    out.toArray()
}

/// 是否句读标点
func isSystemPunct(r: Rune): Bool {
    r == r'，' || r == r',' || r == r'。' || r == r'.' || r == r'！' || r == r'!' || r == r'？' || r == r'?' || r ==
        r'；' || r == r';' || r == r'、'
}
