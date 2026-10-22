package ziyu.frontend

import std.collection.ArrayList
import std.collection.HashMap

/* ============================================================================
 * 多音字消歧（设计文档 §3.3） + 「一 / 不」变调（§3.4 简化）
 *
 * 策略：最长词组匹配优先（词典兜底），未命中回退单字默认读音。
 *   - 内置常用多音字词表（银行 / 行长 / 重庆 / 单县 / 音乐 / 快乐 …）
 *   - 用户扩展接口 addWord(word, pinyins)：注册自定义词组读音
 *   - 附加「一 / 不」变调规则
 *
 * 纯仓颉：HashMap 查表 + Rune 判断，零 FFI。
 * ========================================================================== */

/// 词组最大匹配长度
const MAX_WORD_LEN: Int64 = 4

/// 多音字消歧器
public class PolyphoneResolver {
    private let words: HashMap<String, Array<String>>

    public init() {
        let w = HashMap<String, Array<String>>()
        buildWordDict(w)
        this.words = w
    }

    /// 用户扩展：注册 / 覆盖一个词组的逐字读音（带调数字调，如 ["yin2","hang2"]）
    public func addWord(word: String, pinyins: Array<String>): Unit {
        words.add(word, pinyins)
    }

    /// 从 tokens[i] 起做最长词组匹配
    ///
    /// - returns: (消耗的 Word token 数, 匹配到的拼音序列)；未命中返回 (0, None)
    public func resolve(tokens: Array<Token>, i: Int64): (Int64, ?Array<String>) {
        // 仅收集「单字」Word token，遇非单字或非 Word 即停
        let texts = ArrayList<String>()
        var j = i
        while (j < tokens.size && isSingleWordToken(tokens[j])) {
            texts.add(tokens[j].text)
            j++
        }
        var len = if (texts.size > MAX_WORD_LEN) {
            MAX_WORD_LEN
        } else {
            texts.size
        }
        while (len >= 2) {
            var key = ""
            for (k in 0..len) {
                key += texts[k]
            }
            match (words.get(key)) {
                case Some(p) => return (len, p)
                case None => ()
            }
            len--
        }
        (0, None)
    }
}

/// 是否「单字 Word」token（中文单字，用于词组匹配）
func isSingleWordToken(t: Token): Bool {
    match (t.kind) {
        case Word => t.text.toRuneArray().size == 1
        case _ => false
    }
}

/// 内置多音字词组表：每行「词 + 逐字带调数字调」，空白分隔
let POLYPHONE_WORDS_RAW: String = "银行 yin2 hang2\n" + "行长 hang2 zhang3\n" + "重庆 chong2 qing4\n" +
    "重新 chong2 xin1\n" + "重复 chong2 fu4\n" + "重要 zhong4 yao4\n" + "重量 zhong4 liang4\n" + "音乐 yin1 yue4\n" +
    "乐队 yue4 dui4\n" + "快乐 kuai4 le4\n" + "长江 chang2 jiang1\n" + "成长 cheng2 zhang3\n" + "长大 zhang3 da4\n" +
    "调查 diao4 cha2\n" + "调整 tiao2 zheng3\n" + "空调 kong1 tiao2\n" + "尽管 jin3 guan3\n" + "尽力 jin4 li4\n" +
    "种子 zhong3 zi5\n" + "种植 zhong4 zhi2\n" + "头发 tou2 fa5\n" + "长发 chang2 fa4\n" + "学校 xue2 xiao4\n" +
    "校长 xiao4 zhang3\n" + "将军 jiang1 jun1\n" + "将来 jiang1 lai2\n" + "便宜 pian2 yi5\n" + "方便 fang1 bian4\n" +
    "处理 chu3 li3\n" + "到处 dao4 chu4\n" + "归还 gui1 huan2\n" + "还有 hai2 you3\n" + "关系 guan1 xi5\n" +
    "系统 xi4 tong3\n" + "恶劣 e4 lie4\n" + "厌恶 yan4 wu4\n" + "记载 ji4 zai3\n" + "载重 zai4 zhong4\n" +
    "血压 xue4 ya1\n" + "血液 xue4 ye4\n" + "照片 zhao4 pian4\n" + "卡片 ka3 pian4\n" + "露面 lou4 mian4\n" +
    "露天 lu4 tian1\n" + "教书 jiao1 shu1\n" + "教育 jiao4 yu4\n" + "传说 chuan2 shuo1\n" + "传记 zhuan4 ji4\n" +
    "当心 dang1 xin1\n" + "当作 dang4 zuo4\n" + "好奇 hao4 qi2\n" + "爱好 ai4 hao4\n" + "相片 xiang4 pian4\n" +
    "相互 xiang1 hu4\n" + "数学 shu4 xue2\n" + "数量 shu4 liang4\n" + "中间 zhong1 jian1\n" + "中毒 zhong4 du2\n" +
    "着急 zhao2 ji2\n" + "着火 zhao2 huo3\n" + "行走 xing2 zou3\n" + "儿子 er2 zi5\n" + "我们 wo3 men5\n" +
    "你们 ni3 men5\n" + "他们 ta1 men5\n" + "朋友 peng2 you5\n" + "东西 dong1 xi5"

/// 解析内置词组表到 HashMap
func buildWordDict(w: HashMap<String, Array<String>>): Unit {
    for (line in POLYPHONE_WORDS_RAW.split("\n")) {
        let parts = line.split(" ")
        if (parts.size < 2) {
            continue
        }
        let pys = ArrayList<String>()
        for (k in 1..parts.size) {
            if (parts[k].size > 0) {
                pys.add(parts[k])
            }
        }
        if (pys.size > 0) {
            w.add(parts[0], pys.toArray())
        }
    }
}

// ── 变调规则（一 / 不 + 三声连读） ──

/// 对整段音素序列应用变调（无停顿边界版本，便于单独使用）
public func applyToneSandhi(phonemes: Array<String>): Array<String> {
    applyToneRange(phonemes, 0, phonemes.size)
    phonemes
}

/// 按停顿边界分段应用变调（标点 / 顿处的变调链断开）
///
/// - param pauses: 每个音素之后的停顿时长（ms），>0 表示该音素后为句读边界
public func applyToneSandhiByPauses(phonemes: Array<String>, pauses: Array<Int64>): Array<String> {
    var start: Int64 = 0
    for (k in 0..phonemes.size) {
        let isBreak = k == phonemes.size - 1 || (k < pauses.size && pauses[k] > 0)
        if (isBreak) {
            applyToneRange(phonemes, start, k + 1)
            start = k + 1
        }
    }
    phonemes
}

/// 对 [lo, hi) 区间应用变调
///
/// ① 一(yi1)：后接去声(4) → 阳平(yi2)；后接阴平/阳平/上声(1/2/3) → 去声(yi4)
/// ② 不(bu4)：后接去声(4) → 阳平(bu2)
/// ③ 三声连读：上声(3) + 上声(3) → 前一个变阳平(2)（如 你好 ni2 hao3）
func applyToneRange(phonemes: Array<String>, lo: Int64, hi: Int64): Unit {
    // ① 一 / 不（仅在本段内判断后接声调）
    for (k in lo..hi) {
        let (base, tone) = splitTone(phonemes[k])
        let nt = if (k + 1 < hi) {
            toneOf(phonemes[k + 1])
        } else {
            0
        }
        if (base == "yi" && tone == 1) {
            if (nt == 4) {
                phonemes[k] = "yi2"
            } else if (nt == 1 || nt == 2 || nt == 3) {
                phonemes[k] = "yi4"
            }
        } else if (base == "bu" && tone == 4) {
            if (nt == 4) {
                phonemes[k] = "bu2"
            }
        }
    }
    // ② 三声连读：3 + 3 → 前一个变阳平(2)
    for (k in lo..hi) {
        if (k + 1 < hi) {
            let (base, tone) = splitTone(phonemes[k])
            if (tone == 3 && toneOf(phonemes[k + 1]) == 3) {
                phonemes[k] = base + "2"
            }
        }
    }
}

/// 取音素末尾声调数字（无则 0）
func toneOf(p: String): Int64 {
    let runes = p.toRuneArray()
    if (runes.size == 0) {
        return 0
    }
    let v = digitValue(runes[runes.size - 1])
    if (v >= 1 && v <= 5) {
        v
    } else {
        0
    }
}

/// 拆分音素为 (基元, 声调)，如 "yi1" → ("yi", 1)
func splitTone(p: String): (String, Int64) {
    let runes = p.toRuneArray()
    if (runes.size == 0) {
        return (p, 0)
    }
    let v = digitValue(runes[runes.size - 1])
    if (v >= 1 && v <= 5) {
        (String(Array<Rune>(runes.size - 1, {x => runes[x]})), v)
    } else {
        (p, 0)
    }
}
