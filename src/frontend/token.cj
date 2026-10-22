package ziyu.frontend

/* ============================================================================
 * Token 数据类型
 *
 * 分词产物：每个 token 携带文本片段与种类。种类用于后续音素转换与韵律处理：
 *   - Word：中文单字或英文单词（合成基本单元）
 *   - Number：连续数字串（M5 转中文读法）
 *   - Punctuation：标点（M2 起映射为停顿时长）
 *   - Whitespace：空白（合成时用作词间停顿）
 * ========================================================================== */

/// token 种类
public enum TokenKind {
    | Word        // 词/字（中文单字或英文单词）
    | Number      // 数字串
    | Punctuation // 标点
    | Whitespace  // 空白
}

/// 一个分词单元
public struct Token {
    public let text: String
    public let kind: TokenKind
    public init(text: String, kind: TokenKind) {
        this.text = text
        this.kind = kind
    }
}