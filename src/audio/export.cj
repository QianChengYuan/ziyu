package ziyu.audio

import audio4cj.pcm.AudioBuffer
import audio4cj.pcm.wavBytes

/* ============================================================================
 * 音频导出 —— 复用 audio4cj.pcm.wavBytes（纯仓颉 WAV 打包）
 *
 * ziyu 不重复实现 RIFF/WAVE 头组装，直接委派给上游已验证的实现，
 * 保持"合成产物 → WAV 字节"链路单一来源。
 * ========================================================================== */

/// 把合成结果打包成内存中的 WAV 字节（PCM 整型）。
///
/// - param buffer: 合成产出的 f32 交错 PCM
/// - param bitsPerSample: 位深，默认 16（最通用交换格式）
public func toWavBytes(buffer: AudioBuffer, bitsPerSample!: Int64 = 16): Array<UInt8> {
    wavBytes(buffer, bitsPerSample: bitsPerSample)
}