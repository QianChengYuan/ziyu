package ziyu.core

import audio4cj.pcm.AudioBuffer
import std.collection.concurrent.ArrayBlockingQueue

/* ============================================================================
 * 流式合成句柄
 *
 * 生产者（合成线程）逐音素把 AudioBuffer 片段 push 到阻塞队列，
 * 消费者（播放线程）阻塞取片段播放；None 为结束哨兵。
 *
 * 用 std.collection.concurrent.ArrayBlockingQueue（纯仓颉标准库），
 * ziyu 核心不引入任何 FFI。
 * ========================================================================== */

/// 流式合成句柄：逐块产出 AudioBuffer
public class SynthesisStream {
    private let queue: ArrayBlockingQueue<?AudioBuffer>

    public init(queue: ArrayBlockingQueue<?AudioBuffer>) {
        this.queue = queue
    }

    /// 阻塞取下一块；返回 None 表示合成结束
    public func nextChunk(): ?AudioBuffer {
        queue.remove()
    }

    /// 非阻塞尝试取；返回 None 表示当前暂无数据
    public func tryNextChunk(): Option<?AudioBuffer> {
        queue.tryRemove()
    }
}