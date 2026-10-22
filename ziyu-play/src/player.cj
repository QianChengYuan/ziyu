package ziyu_play

import play4cj.core.PcmFormat
import play4cj.core.PcmSink
import ziyu.core.SynthesisStream

/* ============================================================================
 * ZiyuPlayer —— 流式合成 → PcmSink 桥接播放器
 *
 * 阻塞拉取 SynthesisStream 的逐块 AudioBuffer，喂入 play4cj 的 PcmSink
 * （如 WaveOutStreamSink）实现"边合成边播放"。合成线程与播放消费在同一线程
 * 顺序驱动：nextChunk 阻塞等合成线程产块，write 即时喂入设备。
 * ========================================================================== */

/// 流式合成播放器
public class ZiyuPlayer {
    private let sink: PcmSink
    public init(sink: PcmSink) { this.sink = sink }

    /// 播放流式合成结果；阻塞直到合成结束，返回总帧数
    ///
    /// - param stream: ziyu 流式合成句柄
    /// - param sampleRate/channels: 告知后端的 PCM 格式
    public func play(stream: SynthesisStream, sampleRate: Int64, channels: Int64): Int64 {
        sink.onFormat(PcmFormat(sampleRate, channels))
        var totalFrames: Int64 = 0
        while (true) {
            match (stream.nextChunk()) {
                case Some(chunk) =>
                    sink.write(chunk)
                    totalFrames += chunk.frameCount
                case None =>
                    break
            }
        }
        sink.close()
        totalFrames
    }
}