package ziyu.frontend

import std.collection.ArrayList
import std.unicode.*

/* ============================================================================
 * 分词器
 *
 * 中英文混合分词策略（M1）：
 *   - 中文汉字（CJK 基本区 U+4E00..U+9FFF）：每字一个 Word token
 *   - 英文字母（isLetter 且非 CJK）：连续字母合并为一个 Word token
 *   - 数字（isNumber）：连续数字合并为一个 Number token
 *   - 空白（isWhiteSpace）：连续空白合并为一个 Whitespace token
 *   - 其余：每字符一个 Punctuation token
 *
 * 纯仓颉：仅用 std.unicode 的 Rune 分类与 Array<Rune> 切片，零 FFI。
 * ========================================================================== */

/// 分词器接口
public interface Tokenizer {
    func tokenize(text: String): Array<Token>
}

/// 中英文混合分词器
public class MixedTokenizer <: Tokenizer {
    public init() {}

    public func tokenize(text: String): Array<Token> {
        let tokens = ArrayList<Token>()
        let runes = text.toRuneArray()
        let n = runes.size
        var i = 0
        while (i < n) {
            let r = runes[i]
            if (r.isWhiteSpace()) {
                var j = i + 1
                while (j < n && runes[j].isWhiteSpace()) {
                    j++
                }
                tokens.add(Token(runesToString(runes, i, j), TokenKind.Whitespace))
                i = j
            } else if (isCjk(r)) {
                // 中文每字一个 token
                tokens.add(Token(r.toString(), TokenKind.Word))
                i++
            } else if (r.isLetter()) {
                // 英文连续字母合并
                var j = i + 1
                while (j < n && runes[j].isLetter() && !isCjk(runes[j])) {
                    j++
                }
                tokens.add(Token(runesToString(runes, i, j), TokenKind.Word))
                i = j
            } else if (r.isNumber()) {
                var j = i + 1
                while (j < n && runes[j].isNumber()) {
                    j++
                }
                tokens.add(Token(runesToString(runes, i, j), TokenKind.Number))
                i = j
            } else {
                tokens.add(Token(r.toString(), TokenKind.Punctuation))
                i++
            }
        }
        tokens.toArray()
    }

    // CJK 基本汉字范围判断
    private func isCjk(r: Rune): Bool {
        let c = UInt32(r)
        c >= UInt32(0x4E00) && c <= UInt32(0x9FFF)
    }

    // 把 runes[start, end) 拼成 String
    private func runesToString(runes: Array<Rune>, start: Int64, end: Int64): String {
        if (end - start == 1) {
            return runes[start].toString()
        }
        let part = Array<Rune>(end - start, { k => runes[start + k] })
        String(part)
    }
}