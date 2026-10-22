package ziyu_example_local

// examples/local —— 本地合成示例（纯仓颉，零 FFI）
//
// 演示：文本归一化 → 前端（音素+韵律）→ 本地共振峰 backend → WAV；
// 另含流式合成与云端回环（传输层注入）演示。

import std.env.getVariable
import std.fs.File
import std.fs.Path
import ziyu.Tts
import ziyu.audio.toWavBytes
import ziyu.backend.CloudBackend
import ziyu.backend.EspeakBackend
import ziyu.backend.LoopbackTransport
import ziyu.backend.SystemBackend
import ziyu.frontend.DefaultFrontend
import ziyu.frontend.DefaultNormalizer

main(): Int64 {
    let text = "你好，欢迎使用仓颉编程语言。欢迎使用字语"
    let lang = "zh-CN"

    // ── ⓪ 文本归一化 TN：数字/日期/金额/分数/百分号 → 中文读法 ──
    println("=== 文本归一化 TN ===")
    let tn = DefaultNormalizer()
    let cases = [
        "订单号2026，共3.5元。",
        "发布日2026/10/21，折扣50%。",
        "电话13800138000，订1/2份。",
        "总价¥1999，质保2年。",
        "编号100001，共120人，第10名。"
    ]
    for (c in cases) {
        println("${c} → ${tn.normalize(c, lang)}")
    }

    // ── ① 文本前端（护城河）：归一化 → 分词 → 音素 + 韵律 ──
    println("=== 文本前端 ===")
    let frontend = DefaultFrontend()
    let fe = frontend.process(text, lang)
    println("归一化：${fe.text}")
    print("音素：")
    for (p in fe.phonemes) {
        print("${p.symbol}")
        if (p.pauseAfterMs > 0) {
            print("(${p.pauseAfterMs}ms)")
        }
        print(" ")
    }
    println()
    println("音素数：${fe.phonemes.size}")

    // ── 多音字消歧 + 变调（一/不 + 三声连读，按停顿分段） ──
    println("=== 多音字 & 变调 ===")
    let phCases = ["银行行长在重庆", "一个不好的一定", "你好我也想买水果", "你好，我也想买水果", "这是花儿吗",
        "你去哪儿啊", "儿子在家"]
    for (pc in phCases) {
        let pr = frontend.process(pc, lang)
        print("${pc} → ")
        for (pp in pr.phonemes) {
            print("${pp.symbol} ")
        }
        println()
    }

    // ── ② 统一调度层：前端产出 → backend → PCM ──
    println("=== Backend ===")
    let tts = Tts()
    let cap = tts.capabilities()
    println("后端：${cap.name}")
    println("采样率：${cap.sampleRate} Hz，声道：${cap.channels}")
    println("流式：${cap.streaming}，离线：${cap.offline}，native：${cap.native}")

    // 离线整段合成 → WAV 字节 → 写文件
    let buf = tts.speak(text, language: lang)
    let wav = toWavBytes(buf)
    let outPath = Path("output.wav")
    File.writeTo(outPath, wav)
    println("已生成 ${outPath.toString()}，共 ${wav.size} 字节")

    // ── ③ 流式合成演示（纯仓颉，逐块拉取，不播放） ──
    println("=== 流式合成 ===")
    let stream = tts.speakStream(text, language: lang)
    var chunkCount = 0
    var streamFrames = 0
    while (true) {
        match (stream.nextChunk()) {
            case Some(chunk) =>
                chunkCount += 1
                streamFrames += chunk.frameCount
            case None => break
        }
    }
    println("分块数：${chunkCount}，总帧数：${streamFrames}")

    // ── ④ 云端 backend（MVP2）：传输层依赖注入 + 回环验证 ──
    println("=== 云端 Backend（回环传输）===")
    let cloudTts = Tts(backend: CloudBackend(transport: LoopbackTransport()))
    let cloudCap = cloudTts.capabilities()
    println("后端：${cloudCap.name}，联网：${!cloudCap.offline}，native：${cloudCap.native}")
    let cloudBuf = cloudTts.speak(text, language: lang)
    println("云端整段帧数：${cloudBuf.frameCount}")
    let cloudStream = cloudTts.speakStream(text, language: lang)
    var cloudChunks = 0
    while (true) {
        match (cloudStream.nextChunk()) {
            case Some(chunk) => cloudChunks += 1
            case None => break
        }
    }
    println("云端流式分块数：${cloudChunks}")

    // ── ⑤ 系统 TTS backend（Windows SAPI，进程调用零 FFI） ──
    println("=== 系统 TTS（SAPI）===")
    let sysTts = Tts(backend: SystemBackend())
    let sysCap = sysTts.capabilities()
    println("后端：${sysCap.name}，离线：${sysCap.offline}，native：${sysCap.native}")
    let sysBuf = sysTts.speak(text, language: lang)
    let sysWav = toWavBytes(sysBuf)
    let sysOut = Path("system_output.wav")
    File.writeTo(sysOut, sysWav)
    println("系统合成：${sysBuf.frameCount} 帧，${sysBuf.sampleRate} Hz → ${sysOut.toString()}（${sysWav.size} 字节）")

    // ── ⑥ espeak-ng backend（跨平台命令行；路径可经 ESPEAK_NG 指定） ──
    println("=== espeak-ng ===")
    let esCmd = match (getVariable("ESPEAK_NG")) {
        case Some(p) => p
        case None => "espeak-ng"
    }
    let esBe = EspeakBackend(command: esCmd, voice: "cmn")
    if (esBe.isAvailable()) {
        let esTts = Tts(backend: esBe)
        let esBuf = esTts.speak(text, language: lang)
        let esWav = toWavBytes(esBuf)
        let esOut = Path("espeak_output.wav")
        File.writeTo(esOut, esWav)
        println(
            "espeak 合成：${esBuf.frameCount} 帧，${esBuf.sampleRate} Hz → ${esOut.toString()}（${esWav.size} 字节）")
    } else {
        println("espeak-ng 不可用（设 ESPEAK_NG 指向可执行文件，或加入 PATH）")
    }
    return 0
}
