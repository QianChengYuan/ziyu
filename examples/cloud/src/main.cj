package ziyu_example_cloud

// examples/cloud —— 云端合成示例
//   ① Mock 链路（无网络）验证 CloudTransport → CloudBackend → Tts
//   ② 真实腾讯云 TextToVoice（密钥经环境变量注入，不落库）
//      设 TENCENT_SECRET_ID / TENCENT_SECRET_KEY 后运行即走真实请求

import std.env.getVariable
import std.fs.File
import std.fs.Path
import ziyu.Tts
import ziyu.audio.toWavBytes
import ziyu.backend.CloudBackend
import ziyu_cloud.MockTransport
import ziyu_cloud.TencentCloudTransport
import ziyu_cloud.TencentTtsConfig

main(): Int64 {
    // ── ① Mock 链路（无网络） ──
    println("=== ziyu-cloud mock 链路 ===")
    let mockTts = Tts(backend: CloudBackend(transport: MockTransport()))
    let cap = mockTts.capabilities()
    println("后端：${cap.name}，联网：${!cap.offline}，native：${cap.native}，采样率：${cap.sampleRate}")

    let buf = mockTts.speak("你好世界", language: "zh-CN")
    println("整段帧数：${buf.frameCount}，采样率：${buf.sampleRate}")

    let st = mockTts.speakStream("你好世界", language: "zh-CN")
    var chunks = 0
    var frames = 0
    while (true) {
        match (st.nextChunk()) {
            case Some(c) =>
                chunks += 1
                frames += c.frameCount
            case None => break
        }
    }
    println("流式分块：${chunks}，总帧：${frames}")

    // ── ② 真实腾讯云（需环境变量密钥） ──
    println("=== 腾讯云 TextToVoice ===")
    let sid = getVariable("TENCENT_SECRET_ID")
    let skey = getVariable("TENCENT_SECRET_KEY")
    match (sid) {
        case Some(id) => match (skey) {
            case Some(key) =>
                let cfg = TencentTtsConfig(id, key)
                let cloudTts = Tts(backend: CloudBackend(transport: TencentCloudTransport(cfg)))
                let text = "你好，欢迎使用仓颉编程语言。"
                let audio = cloudTts.speak(text, language: "zh-CN")
                let wav = toWavBytes(audio)
                let out = Path("tencent_output.wav")
                File.writeTo(out, wav)
                println("腾讯云合成：${audio.frameCount} 帧 → ${out.toString()}（${wav.size} 字节）")
            case None => println("未设置 TENCENT_SECRET_KEY，跳过真实请求")
        }
        case None => println("未设置 TENCENT_SECRET_ID / TENCENT_SECRET_KEY，跳过真实请求")
    }
    return 0
}
