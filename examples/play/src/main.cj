package ziyu_example_play

// examples/play —— 实时播放示例
//
// 演示：文本 → 流式共振峰合成 → play4cj WaveOut 边产边播。
// 播放桥接由 ziyu-play 模块的 ZiyuPlayer 提供（native 能力隔离在调用侧）。

import play4cj.winsound.WaveOutStreamSink
import ziyu.core.SynthesisOptions
import ziyu.core.TextToSpeech
import ziyu.core.Voice
import ziyu.core.VoiceGender
import ziyu.synth.FormantSynthesizer
import ziyu_play.ZiyuPlayer

main(): Int64 {
    let text = "你好，欢迎使用仓颉编程语言。"

    println("=== 流式合成 + 实时播放 ===")
    let engine = FormantSynthesizer()
    let tts = TextToSpeech(engine)
    let voice = Voice("zh-CN-formant", "zh-CN", 22050, VoiceGender.Neutral)
    let options = SynthesisOptions(1.0, 1.0, 0.8)
    println("引擎：${tts.engineName()}，采样率：${voice.sampleRate} Hz")
    println("开始流式合成并播放...")

    let stream = tts.speakStream(text, voice, options: options)
    let sink = WaveOutStreamSink()
    let player = ZiyuPlayer(sink)
    let total = player.play(stream, voice.sampleRate, 1)

    let durationMs = total * 1000 / voice.sampleRate
    println("播放完成，总帧数：${total}，时长约 ${durationMs} ms")
    return 0
}