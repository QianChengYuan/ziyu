# ziyu（字语）—— 仓颉中文文本前端 + TTS 统一调度层

> **ziyu = 字语：文字在说话。**「字」是文字，「语」是让文字开口——把汉语的字、音、调讲对，是这套库的起点。
>
> 不做合成引擎，做 **中文文本前端（护城河）+ Backend 抽象调度层**。
> 声学引擎（系统 TTS / 云端 API / 本地 ONNX）都有成熟方案，而"念得对不对"取决于文本前端。
> ziyu 把中文前端做深，把合成引擎做成可替换的 backend。

- 核心库 **纯仓颉、零 FFI / 零 unsafe / 零 @C**，仅依赖 `audio4cj`
- 前端产出统一契约 `FrontendResult`（归一化文本 + 音素 + 韵律）
- **5 个合成引擎中 4 个已实测可用**：本地共振峰 / 系统 TTS / eSpeak NG / 腾讯云
- Backend 可插拔，网络与 native 能力隔离在独立模块（`ziyu-cloud` / `ziyu-play`），不污染核心

## 支持引擎

| 引擎 | 说明 | 状态 | 外部依赖 | 离线可用 |
|---|---|---|---|---|
| `LocalBackend` | 共振峰规则合成 | ✅ 已实测 · **纯仓颉** | 无 | 是 |
| `SystemBackend` | 系统 TTS（Windows SAPI 等） | ✅ 已实测 | 系统语音 API | 是 |
| `EspeakBackend` | eSpeak NG 合成 | ✅ 已实测 | `espeak-ng` | 是 |
| `CloudBackend` | 云端合成（腾讯云） | ✅ 已实测（联网通过） | `stdx.net.*` + 密钥 | 否 |
| `OnnxBackend` | 神经声学模型（VITS / Kokoro 等） | ⏸ 计划中（v1.1） | onnxruntime + 模型权重 | 是 |

切换引擎只需替换 backend，前端产出的 `FrontendResult` 对所有引擎一致：

```cangjie
import ziyu.Tts
import ziyu.backend.*

let tts = Tts(LocalBackend())      // 默认：纯仓颉共振峰
// let tts = Tts(SystemBackend())  // 系统 TTS
// let tts = Tts(EspeakBackend())  // eSpeak NG
// let tts = Tts(CloudBackend())   // 腾讯云（需密钥）
let buf = tts.speak("你好，欢迎使用仓颉编程语言。")
```

> `SystemBackend` / `EspeakBackend` 涉及系统 API 与外部程序，属于可选 backend，
> 与 `ziyu-cloud` / `ziyu-play` 一样不进入核心依赖；不启用即不影响"纯仓颉"承诺。

## 架构

```
文本 ──▶ 文本前端（ziyu.frontend，纯仓颉）──▶ FrontendResult
                                                   │
                                                   ▼
                          Tts 门面（ziyu.Tts）─▶ TtsBackend 接口
                                                   │
        ┌──────────────┬───────────────┬───────────┼────────────┐
        ▼              ▼               ▼           ▼            ▼
 LocalBackend   SystemBackend   EspeakBackend  CloudBackend  （计划中）
 （共振峰）      （SAPI）        （espeak-ng）   （腾讯云）     ONNX
   纯仓颉          系统 API        外部程序        stdx.net    待 runtime
        │              │               │           │
        └──────────────┴───────┬───────┴───────────┘
                               ▼
                             PCM ──▶ 音频输出（ziyu-play → play4cj/winsound4cj）
```

| 包 / 模块 | 职责 | 依赖 |
|---|---|---|
| `ziyu.frontend` | 归一化 / 分词 / 音素 / 韵律 / 多音字 / 变调 / 儿化 / 轻声 | 纯仓颉零依赖 |
| `ziyu`（`tts.cj`） | `Tts` 门面：前端 → backend → PCM | `audio4cj` |
| `ziyu.backend` | `TtsBackend` 接口 + Local / System / Espeak / Cloud 四个实现 | `audio4cj`（云端另需 stdx） |
| `ziyu.synth` | 共振峰规则合成（`FormantSynthesizer`） | 纯仓颉 |
| `ziyu.audio` | WAV 打包（复用 `audio4cj.pcm`） | `audio4cj` |
| `ziyu-play`（模块） | 流式播放适配（`ZiyuPlayer`） | `play4cj`/`winsound4cj` |
| `ziyu-cloud`（模块） | 腾讯云 TTS 接入 | `stdx.net.*` |

## 环境要求

- 仓颉工具链 **cjc / cjpm ≥ 1.1.0**（核心 `ziyu` 声明 `1.1.0`）
- `ziyu-cloud` 需 **stdx 1.2.0**（`stdx.net.http` / `crypto.digest` / `encoding.*`），用 `cangjie-coding` 技能的 `setup_stdx.py` 配置
- `SystemBackend`：依赖系统语音引擎（Windows 自带 SAPI，无需安装）
- `EspeakBackend`：需本机安装 [eSpeak NG](https://github.com/espeak-ng/espeak-ng) 并可在 PATH 中找到 `espeak-ng`

## 快速开始

```cangjie
import ziyu.Tts
import ziyu.audio.toWavBytes
import std.fs.File

main(): Int64 {
    let tts = Tts()                                  // 默认 LocalBackend（共振峰）
    let buf = tts.speak("你好，欢迎使用仓颉编程语言。")  // 前端 → 合成 → PCM
    File.writeTo("output.wav", toWavBytes(buf))
    return 0
}
```

只跑前端（不合成）：

```cangjie
import ziyu.frontend.DefaultFrontend

let fe = DefaultFrontend().process("2026年，你好吗？", "zh-CN")
println(fe.text)                          // 归一化文本
for (p in fe.phonemes) { println(p.symbol) }  // 音素（含韵律停顿）
```

## 示例

整理于 `examples/`，各为独立工程：

| 示例 | 说明 | 运行 |
|---|---|---|
| `examples/local` | 本地合成（纯仓颉）：TN / 前端 / 多音字变调 / 流式 / 云端回环 | `cd examples/local && cjpm run` |
| `examples/play` | 实时播放：流式合成 → WaveOut 边产边播（需 Windows 音频） | `cd examples/play && cjpm run` |
| `examples/cloud` | 云端合成：Mock 链路 + 腾讯云 TextToVoice（需密钥） | `cd examples/cloud && cjpm run` |

云端示例密钥经环境变量注入（不落库）：`TENCENT_SECRET_ID` / `TENCENT_SECRET_KEY`。

## 目录结构

```
ziyu/
├── src/
│   ├── frontend/        # 中文文本前端（护城河）
│   │   ├── normalizer.cj    # 归一化 TN（数字/日期/金额/…）
│   │   ├── number_reader.cj # 中文数字读法引擎
│   │   ├── tokenizer.cj     # 中英混合分词
│   │   ├── phonemizer.cj    # 音素转换（词典 + 儿化 + 轻声 + 韵律）
│   │   ├── polyphone.cj     # 多音字消歧 + 变调
│   │   ├── pipeline.cj      # 前端流水线（TextFrontend）
│   │   └── frontend.cj      # FrontendResult / Phoneme
│   ├── backend/         # Backend 抽象层（4 个已实现引擎）
│   │   ├── backend.cj       # TtsBackend / BackendCapability / AudioStream
│   │   ├── local.cj         # LocalBackend（共振峰，纯仓颉）
│   │   ├── system.cj        # SystemBackend（SAPI 等系统 TTS）
│   │   ├── espeak.cj        # EspeakBackend（espeak-ng）
│   │   └── cloud.cj         # CloudBackend / CloudTransport / Loopback
│   ├── synth/           # 共振峰合成引擎
│   ├── core/            # 核心类型与流（SynthesisEngine 等）
│   ├── audio/           # WAV 导出
│   └── tts.cj           # Tts 门面（用户 API）
├── examples/            # 示例（local / play / cloud）
├── ziyu-play/           # 播放适配模块（native）
├── docs/                # 文档
├── cjpm.toml
└── NOTICE
```

```
ziyu-cloud/              # 云端接入独立模块（同级目录）
├── src/
│   ├── tencent.cj           # TencentCloudTransport（REST TextToVoice）
│   ├── tc3.cj               # TC3-HMAC-SHA256 签名
│   ├── pcm.cj               # PCM16 → Float32
│   ├── pronunciation.cj     # 云端读音修正（同音替换）
│   └── mock.cj              # MockTransport（无网络验证）
└── example -> 已迁入 ziyu/examples/cloud
```

## 文档

- [文档索引](docs/README.md)
- [前端指南](docs/前端指南.md) —— 归一化 / 音素 / 多音字 / 变调 / 扩展
- [后端与调度](docs/后端与调度.md) —— `Tts` 门面 / `TtsBackend` / 自定义 backend
- [云端接入](docs/云端接入.md) —— 选型 / 腾讯云参数 / TC3 签名 / 读音修正

## 路线图

- **v1.0**：4 个引擎（Local / System / Espeak / Cloud）+ 中文前端
- **v1.1**：`OnnxBackend` —— 神经声学模型本地推理（onnxruntime + 模型），补齐高质量离线合成
- 更远：更多中文音色、SSML 支持、方言前端

## 依赖与许可

- 依赖：`audio4cj`（纯仓颉音频编解码）；`ziyu-cloud` 额外依赖 stdx
- 许可：Apache-2.0（见 `LICENSE`）；第三方数据致谢见 `NOTICE`
