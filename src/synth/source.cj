package ziyu.synth

import std.math.sin
import std.math.cos
import std.random.Random

/* ============================================================================
 * 声源激励
 *
 * 共振峰合成需要两类声源：
 *   1. 浊音激励——声门气流导数模型，开启段 cos(πt) + 闭合段静默
 *   2. 清音激励——白噪声，经共振峰滤波后产生摩擦音/爆破音
 *
 * 纯仓颉：std.math.sin/cos + std.random.Random，零 FFI。
 * ========================================================================== */

/// 浊音声源（Rosenberg 声门**气流**模型，去均值后双极性）
///
/// 频谱约 -12dB/oct（声门气流本征衰减），经输出端唇辐射 +6dB/oct 后净约
/// -6dB/oct。声门气流本身单极性（周期均值≈0.302），此处**减去周期均值**
/// 使其双极性，避免经滤波器 DC 增益（非零）放大成直流偏置。
/// - param phase: 当前相位（弧度），由合成器逐样本递进
/// - returns: 瞬时激励值（双极性，约 [-0.30, 0.70]）
public func voicedSource(phase: Float64): Float64 {
    let twoPi = 2.0 * 3.141592653589793
    let p = phase / twoPi          // 周期内归一化相位 [0, 1)
    let tp = 0.4                   // 声门开相占比
    let tn = 0.16                  // 声门收相占比
    var g = 0.0
    if (p < tp) {
        g = 0.5 * (1.0 - cos(3.141592653589793 * p / tp))
    } else if (p < tp + tn) {
        g = cos(3.141592653589793 * (p - tp) / (2.0 * tn))
    } else {
        g = 0.0
    }
    // 去均值（周期均值≈0.302）→ 双极性，消除直流分量
    g - 0.302
}

/// 白噪声源（清音激励）
///
/// 包装 std.random.Random，输出 [-1, 1] 均匀白噪声。
/// Random 非线程安全，每个合成器实例独占一个 NoiseSource。
public class NoiseSource {
    private let rng: Random
    public init(seed!: UInt64 = 12345) {
        rng = Random(seed)
    }
    /// 返回 [-1.0, 1.0) 的随机浮点
    public func next(): Float64 {
        rng.nextFloat64() * 2.0 - 1.0
    }
}