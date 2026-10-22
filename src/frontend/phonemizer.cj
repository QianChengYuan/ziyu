package ziyu.frontend

import std.collection.ArrayList
import std.collection.HashMap

/* ============================================================================
 * 音素转换（token → 音素 + 韵律）
 *
 * 内置 20903 条完整汉字→拼音词典（MIT 许可，复刻自 pinyin4cj 1.0.5）。
 *
 * 解析循环是唯一知道「token ↔ 音素」对应关系的地方，故把韵律（标点停顿）
 * 与音素一并产出，保证「多 token → 少音素」映射（多音字词组、儿化合并）
 * 下停顿仍与音素正确对齐。
 *
 *   - 多音字消歧（§3.3）：最长词组匹配（PolyphoneResolver）
 *   - 儿化音（§3.4）：汉字 + 儿（儿后非「子」）合并为一个儿化音节（韵母 + r）
 *   - 语气词轻声（§3.4）：句末语气词强制轻声（基于字形判定）
 *   - 韵律：标点 → 其前音素之后的停顿时长
 *
 * 变调（一 / 不 + 三声连读）由 pipeline 在停顿分段后应用（见 polyphone.cj）。
 * 带调符号转数字调拼音（如 "nǐ"→"ni3"），供 FormantSynthesizer 消费。
 * 纯仓颉：HashMap 查表 + Rune 判断，零 FFI。
 * ========================================================================== */

/// 音素转换接口：token 序列 → 音素序列（含韵律）
public interface Phonemizer {
    func toPhonemes(tokens: Array<Token>, language: String): Array<Phoneme>
}

/// 句末语气词（强制轻声）
let FINAL_PARTICLES: Array<String> = [
    "吗",
    "呢",
    "吧",
    "啊",
    "呀",
    "哇",
    "啦",
    "嘛",
    "哦",
    "哟",
    "嗯",
    "哩"
]

/// 词典音素转换器（内置 20903 条拼音词典 + 多音字消歧 + 儿化 + 语气词轻声）
public class DictionaryPhonemizer <: Phonemizer {
    private let dict: HashMap<String, String>
    private let poly: PolyphoneResolver

    public init(poly!: PolyphoneResolver = PolyphoneResolver()) {
        dict = buildPinyinDict()
        this.poly = poly
    }

    /// 用户扩展：注册 / 覆盖自定义词组读音（带调数字调）
    public func addWord(word: String, pinyins: Array<String>): Unit {
        poly.addWord(word, pinyins)
    }

    public func toPhonemes(tokens: Array<Token>, language: String): Array<Phoneme> {
        let result = ArrayList<Phoneme>()
        var i: Int64 = 0
        while (i < tokens.size) {
            let t = tokens[i]
            match (t.kind) {
                case Whitespace => i++
                case Punctuation =>
                    // 标点停顿 → 其前音素
                    markPause(result, punctPauseMs(t.text))
                    i++
                case _ =>
                    if (isHanToken(t) && i + 1 < tokens.size && isCharToken(tokens[i + 1], "儿") && (i + 2 >= tokens
                        .size || !isCharToken(tokens[i + 2], "子"))) {
                        // 儿化：汉字 + 儿 → 一个儿化音节（韵母 + r）
                        result.add(Phoneme(erhua(singlePinyin(t.text)), pauseAfterMs: 0))
                        i += 2
                    } else {
                        // 多音字词组最长匹配
                        let (consumed, matched) = poly.resolve(tokens, i)
                        match (matched) {
                            case Some(pinyins) =>
                                for (p in pinyins) {
                                    result.add(Phoneme(p, pauseAfterMs: 0))
                                }
                                i += consumed
                            case None =>
                                let sym = singlePinyin(t.text)
                                let s = if (isFinalParticle(t.text) && isSentenceEnd(tokens, i)) {
                                    lightTone(sym)
                                } else {
                                    sym
                                }
                                result.add(Phoneme(s, pauseAfterMs: 0))
                                i++
                        }
                    }
            }
        }
        result.toArray()
    }

    /// 单字拼音（未收录则原样保留）
    private func singlePinyin(ch: String): String {
        match (dict.get(ch)) {
            case Some(p) => p
            case None => ch
        }
    }
}

/// 标点停顿写入最后一个音素（取较大者）
func markPause(result: ArrayList<Phoneme>, ms: Int64): Unit {
    if (ms <= 0 || result.size == 0) {
        return
    }
    let last = result.size - 1
    if (ms > result[last].pauseAfterMs) {
        result[last] = Phoneme(result[last].symbol, pauseAfterMs: ms)
    }
}

/// 儿化：韵母后追加 r（如 "hua1" → "hua1r"；后端剥离 r 按原韵母合成）
func erhua(pinyin: String): String {
    if (pinyin.size == 0) {
        return pinyin
    }
    pinyin + "r"
}

/// 强制轻声：保留基元，声调置 5
func lightTone(sym: String): String {
    let (base, _) = splitTone(sym)
    if (base.size == 0) {
        sym
    } else {
        base + "5"
    }
}

/// 是否句末语气词字
func isFinalParticle(ch: String): Bool {
    for (p in FINAL_PARTICLES) {
        if (p == ch) {
            return true
        }
    }
    false
}

/// 是否单字 Word token（汉字）
func isHanToken(t: Token): Bool {
    match (t.kind) {
        case Word => t.text.toRuneArray().size == 1
        case _ => false
    }
}

/// token 是否为指定单字
func isCharToken(t: Token, ch: String): Bool {
    match (t.kind) {
        case Word => t.text == ch
        case _ => false
    }
}

/// 音素对应 token 是否为句末（后无 token 或后接标点）
func isSentenceEnd(tokens: Array<Token>, i: Int64): Bool {
    if (i + 1 >= tokens.size) {
        return true
    }
    match (tokens[i + 1].kind) {
        case Punctuation => true
        case _ => false
    }
}

/// 带调元音字母（ā á ǎ à ē é ě è ī í ǐ ì ō ó ǒ ò ū ú ǔ ù ǖ ǘ ǚ ǜ）
let MARKED_VOWELS: Array<Rune> = [
    r'ā',
    r'á',
    r'ǎ',
    r'à',
    r'ē',
    r'é',
    r'ě',
    r'è',
    r'ī',
    r'í',
    r'ǐ',
    r'ì',
    r'ō',
    r'ó',
    r'ǒ',
    r'ò',
    r'ū',
    r'ú',
    r'ǔ',
    r'ù',
    r'ǖ',
    r'ǘ',
    r'ǚ',
    r'ǜ'
]

/// 无调元音字母（与 MARKED_VOWELS 每 4 个一组对应：a e i o u v）
let UNMARKED_VOWELS: Array<Rune> = [r'a', r'e', r'i', r'o', r'u', r'v']

/// 带调符号拼音 → 数字调拼音（如 "nǐ"→"ni3"，"hǎo"→"hao3"，"mā"→"ma1"）
///
/// 声调编码：1=阴平 2=阳平 3=上声 4=去声 5=轻声（无调符号时默认 5）
func toToneNumber(s: String): String {
    // 先把孤立的 ü 替换为 v（带调的 ǖ-ǜ 在下面统一处理）
    let replaced = s.replace("ü", "v")
    let runes = replaced.toRuneArray()
    for (j in 0..runes.size) {
        let c = runes[j]
        for (idx in 0..MARKED_VOWELS.size) {
            if (MARKED_VOWELS[idx] == c) {
                let tone = idx % 4 + 1
                let baseIdx = (idx - idx % 4) / 4
                runes[j] = UNMARKED_VOWELS[baseIdx]
                return String(runes) + "${tone}"
            }
        }
    }
    // 无带调符号，视为轻声
    replaced + "5"
}

/// 解析 PINYIN_DICT_RAW：汉字行/拼音行严格交替，取首个读音转数字调
func buildPinyinDict(): HashMap<String, String> {
    let lines = PINYIN_DICT_RAW.split("\n")
    let dict = HashMap<String, String>()
    var i: Int64 = 0
    while (i + 1 < lines.size) {
        let key = lines[i]
        let keyRunes = key.toRuneArray()
        if (keyRunes.size == 1) {
            let raw = lines[i + 1]
            if (raw.size > 0 && raw != "null") {
                let first = raw.split(",")[0]
                dict.add(key, toToneNumber(first))
            }
        }
        i += 2
    }
    dict
}
