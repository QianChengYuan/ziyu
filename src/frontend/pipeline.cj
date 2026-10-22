package ziyu.frontend

import std.collection.ArrayList

/* ============================================================================
 * 文本前端流水线
 *
 * 串联 归一化 → 分词 → 音素转换（含韵律）→ 变调，对外提供
 * 「文本 → FrontendResult」一站式入口。
 * Backend 抽象层消费 FrontendResult 生成 PCM。
 * ========================================================================== */

/// 文本前端接口：原始文本 → 前端产出
public interface TextFrontend {
    func process(text: String, language: String): FrontendResult
}

/// 默认前端：归一化 → 分词 → 音素转换（含韵律）→ 变调
public class DefaultFrontend <: TextFrontend {
    private let normalizer: TextNormalizer
    private let tokenizer: Tokenizer
    private let phonemizer: Phonemizer

    public init(
        normalizer!: TextNormalizer = DefaultNormalizer(),
        tokenizer!: Tokenizer = MixedTokenizer(),
        phonemizer!: Phonemizer = DictionaryPhonemizer()
    ) {
        this.normalizer = normalizer
        this.tokenizer = tokenizer
        this.phonemizer = phonemizer
    }

    public func process(text: String, language: String): FrontendResult {
        let normalized = normalizer.normalize(text, language)
        let tokens = tokenizer.tokenize(normalized)
        // 音素 + 韵律（停顿已随音素对齐产出）
        let phonemes = phonemizer.toPhonemes(tokens, language)
        // 变调：抽离符号序列按停顿分段处理，再回填
        let symbols = Array<String>(phonemes.size, {k => phonemes[k].symbol})
        let pauses = Array<Int64>(phonemes.size, {k => phonemes[k].pauseAfterMs})
        applyToneSandhiByPauses(symbols, pauses)
        let out = ArrayList<Phoneme>(phonemes.size)
        for (i in 0..symbols.size) {
            out.add(Phoneme(symbols[i], pauseAfterMs: pauses[i]))
        }
        FrontendResult(normalized, language, out.toArray())
    }
}

/// 标点 → 停顿时长（ms）
func punctPauseMs(punct: String): Int64 {
    if (punct == "，" || punct == "," || punct == "、" || punct == "；" || punct == ";" || punct == "：" || punct == ":") {
        200
    } else if (punct == "。" || punct == "." || punct == "？" || punct == "?" || punct == "！" || punct == "!") {
        400
    } else {
        0
    }
}
