package ziyu.synth

import std.math.exp
import std.math.cos
import std.math.sqrt

/* ============================================================================
 * 共振峰滤波器——二阶节 IIR 谐振器
 *
 * 单个共振峰用一个二阶全极点滤波器实现（"谐振器"结构）：
 *
 *   R = exp(-π·B / Fs)        （极点半径，B 为带宽）
 *   θ = 2π·F / Fs             （极点角度，F 为共振峰频率）
 *   c1 = 2·R·cos(θ)
 *   c2 = R²
 *
 *   差分方程：y[n] = x[n] + c1·y[n-1] - c2·y[n-2]
 *
 * 并联三个 FormantFilter（F1/F2/F3）即得到元音的声道传输函数。
 *
 * **状态继承**：段切换时调用 setCoefficients 仅更新系数，**保留** y1/y2。
 * 避免每段重建对象清零状态导致的输出跳变；reset 仅在整段合成开始时使用。
 * 纯仓颉：std.math.exp + std.math.cos，零 FFI。
 * ========================================================================== */

/// 单个共振峰的二阶节 IIR 滤波器
public class FormantFilter {
    private var c1: Float64 = 0.0
    private var c2: Float64 = 0.0
    private var gain: Float64 = 0.0   // 归一化增益，使峰值增益 |H(e^jθ)|=1
    private var y1: Float64 = 0.0     // y[n-1]
    private var y2: Float64 = 0.0     // y[n-2]

    /// - param frequency: 共振峰频率 Hz
    /// - param bandwidth: 共振峰带宽 Hz
    /// - param sampleRate: 采样率 Hz
    public init(frequency: Float64, bandwidth: Float64, sampleRate: Float64) {
        setCoefficients(frequency, bandwidth, sampleRate)
    }

    /// 更新滤波系数（保留内部状态 y1/y2，用于段切换无瞬态跳变）
    public func setCoefficients(frequency: Float64, bandwidth: Float64, sampleRate: Float64): Unit {
        let pi = 3.141592653589793
        let r = exp(-pi * bandwidth / sampleRate)
        let theta = 2.0 * pi * frequency / sampleRate
        c1 = 2.0 * r * cos(theta)
        c2 = r * r
        // 峰值增益归一化：在共振峰频率处增益=1
        gain = (1.0 - r) * sqrt(1.0 + r * r - 2.0 * r * cos(2.0 * theta))
    }

    /// 处理单个样本
    public func process(x: Float64): Float64 {
        let y = x + c1 * y1 - c2 * y2
        y2 = y1
        y1 = y
        return y * gain
    }

    /// 重置滤波器状态（仅整段合成开始时使用，段切换不要调用）
    public func reset(): Unit {
        y1 = 0.0
        y2 = 0.0
    }
}