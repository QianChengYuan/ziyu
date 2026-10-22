package ziyu.frontend

import std.collection.ArrayList

/* ============================================================================
 * 文本前端产出
 *
 * 前端（护城河）把原始文本变成 backend 可直接消费的「音素序列 + 韵律」：
 *   - 归一化文本：数字/货币/日期等已展开（TN，后续迭代）
 *   - 音素序列：带调拼音（数字调，如 "ni3"），酷本地 backend 精确掌控
 *   - 韵律标注：每个音素之后的停顿时长（ms），MVP 由标点驱动
 *
 * 纯仓颉，零 FFI / 零外部依赖。
 * ========================================================================== */

/// 一个音素单元：音素符号 + 其后停顿时长
public struct Phoneme {
    public let symbol: String // 音素（带调拼音，如 "ni3"）
    public let pauseAfterMs: Int64 // 该音素之后的停顿时长（ms）
    public init(symbol: String, pauseAfterMs!: Int64 = 0) {
        this.symbol = symbol
        this.pauseAfterMs = pauseAfterMs
    }
}

/// 文本前端产出：归一化文本 + 音素序列 + 韵律
public struct FrontendResult {
    public let text: String // 归一化后文本
    public let language: String // 语言标识（如 "zh-CN"）
    public let phonemes: Array<Phoneme> // 音素序列（含韵律）

    public init(text: String, language: String, phonemes: Array<Phoneme>) {
        this.text = text
        this.language = language
        this.phonemes = phonemes
    }

    /// 便捷：仅取音素符号序列（供合成 backend 消费）
    public func symbols(): Array<String> {
        let out = ArrayList<String>(phonemes.size)
        for (p in phonemes) {
            out.add(p.symbol)
        }
        out.toArray()
    }

    /// 是否为空（无音素）
    public func isEmpty(): Bool {
        phonemes.size == 0
    }
}
