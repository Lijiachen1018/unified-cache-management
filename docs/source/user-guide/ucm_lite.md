# UCM Lite 工具介绍

## 1. 概述

**UCM Lite**（即 **UCM Trace Mode**，启用后内部实例化为 `UCMLiteConnector`）是 UCM 提供的一种轻量诊断与评估模式。它在推理期间记录每个请求的 trace，但**不执行任何真实的 KV cache dump/load 操作**。通过收集真实请求流量数据，可以提前模拟 UCM 理论能达到的 KV cache 命中率，从而在投入完整的 UCM 存储方案之前完成评估。

官方文档建议：先用 Trace Mode 收集命中率统计，并与相关项目成员确认后再决定是否采纳 UCM。

### 核心特性

与常规存储型 Connector 不同，Lite Connector 配合一个 Fake Store 工作：

- 计算出与真实 UCM 部署完全一致的 block hash ID。
- 对每个请求在首次 lookup 时记录一条 trace。
- 返回 `0` 外部命中 token（因为没有真实 store 可查），因此不影响推理正确性，也不落盘任何 KV 数据。
- 将全部 KV 传输 hook（`start_load_kv`、`save_kv_layer`、`wait_for_save` 等）实现为 no-op。

### 启用开关

Trace Mode 需要同时开启 UCM 配置中的两个选项：

| 配置项 | 默认值 | 说明 |
| :----- | :------ | :---------- |
| `enable_record_traces` | `false` | 记录每条请求的 trace（timestamp、input_length、output_length、hash_ids）。每个 hash_id 占 32 字节。 |
| `use_lite` | `false` | 切换到 **UCM Lite Connector**，使用跳过全部真实 KV dump/load 操作的 Fake Store。 |

两个开关同时为 `true` 时，`UCMConnector` 内部会实例化 `UCMLiteConnector` 来替代常规 Connector。服务启动日志中出现 `[UC][I] Init UCMLiteConnector.` 即表示 Lite Connector 已生效。

## 2. Trace 日志格式

每个请求在首次 lookup 时产生两行日志：

```text
[UC][I] timestamp: 1234567.890123, request_id: req-42, input_length: 8192, output_length: 128, ucm_block_ids: ['a1b2...', 'c3d4...', ...]
[UC][I] request_id: req-42, hash_time_ms: 0.512, print_time_ms: 0.034
```

| 字段 | 说明 |
| :---- | :---------- |
| `timestamp` | lookup 时刻 `time.perf_counter()` 的值，分析时用于保留请求顺序。 |
| `request_id` | vLLM 请求标识（Lite Connector trace 中有）。 |
| `input_length` | 请求输入 token 数（`request.num_tokens`）。 |
| `output_length` | 请求最大输出 token 数（`request.max_tokens`）。 |
| `ucm_block_ids` | hex 编码的 block hash ID 列表。每个 block 对应 `block_size` 个 token；每个 hash 32 字节。 |
| `hash_time_ms` | 计算 block hash ID 耗时（仅 Lite Connector）。 |
| `print_time_ms` | 格式化/打印该 trace 行的耗时（仅 Lite Connector）。 |

## 3. 使用方法

### 3.1 配置文件

从示例文件 `unified-cache-management/examples/ucm_config_example.yaml` 开始，开启两个选项：

```yaml
enable_record_traces: true
use_lite: true
```

### 3.2 日志配置（可选）

trace 会很大：每个 hash_id 占 32 字节，长请求可能包含大量 block ID。启动服务前可通过环境变量调大日志限制：

| 环境变量 | 默认值 | 说明 |
| :------------------- | :------ | :---------- |
| `UCM_LOG_PATH` | `log` | 每个进程的日志目录（如 `ucm-<pid>.log`）。 |
| `UCM_LOG_MAX_FILES` | `10` | 每进程保留的滚动日志文件数上限。 |
| `UCM_LOG_MAX_SIZE` | `5` | 每个日志文件滚动前的大小上限，单位 **MiB**。记录长请求 trace 时请显著调大。 |
| `UCM_LOG_LEVEL` | `info` | 日志级别。trace 以 `INFO` 级别输出，保持 `info`（或更低以获得更多 debug 输出）。 |

trace 采集运行示例：

```bash
export UCM_LOG_PATH=/workspace/ucm-trace-logs
export UCM_LOG_MAX_SIZE=256      # 256 MiB 每文件
export UCM_LOG_MAX_FILES=50     # 每进程最多保留 50 个滚动文件
export UCM_LOG_LEVEL=info
```

### 3.3 启动推理服务

Trace Mode 以 OpenAI 兼容的 vLLM server 部署，启动方式与正常 UCM 部署相同，唯一的区别是 UCM 配置文件内容。以 Qwen2.5-14B-Instruct 为例：

```bash
vllm serve Qwen/Qwen2.5-14B-Instruct \
  --max-model-len 32000 \
  --tensor-parallel-size 2 \
  --gpu_memory_utilization 0.87 \
  --block_size 128 \
  --trust-remote-code \
  --port 7800 \
  --enforce-eager \
  --no-enable-prefix-caching \
  --kv-transfer-config \
  '{
      "kv_connector": "UCMConnector",
      "kv_role": "kv_both",
      "kv_connector_module_path": "ucm.integration.vllm.ucm_connector",
      "kv_connector_extra_config": {"UCM_CONFIG_FILE": "/workspace/unified-cache-management/examples/ucm_config_example.yaml"}
  }'
```

**⚠️ 请将 `UCM_CONFIG_FILE` 替换为你机器上 trace-mode 配置文件的真实路径。**

服务启动后即可向服务施加生产等价流量。每个请求都会在 UCM 日志目录中产生一条 trace，全程不会 dump 或 load 任何 KV cache。

## 4. 结果分析

### 4.1 运行分析脚本

trace 收集完成后，运行 `benchmarks/auto_trace_analysis.py` 模拟理论 KV cache 命中率。脚本解析 trace 行，并结合 vLLM/UCM 启动时输出的 `available kv cache memory`（或 `current kv cache memory`）和 `tensor_parallel_size`，模拟一个 LRU 多级缓存（HBM → DRAM → FS），估算 UCM 能实现的命中率。

```bash
python benchmarks/auto_trace_analysis.py \
  --service-url <ip:port of vllm service> \
  --log-dir <path to log folder> \
  --block-kv-cache-size <bytes_per_block> \
  --is-mla <true|false> \
  --dram-pool-size-gb <dram_gb> \
  --fs-pool-size-gb <fs_gb>
```

参数说明：

| 参数 | 说明 |
| :------- | :---------- |
| `--service-url` | vLLM `/metrics` 端点（Prometheus）。设置后工具会拉取服务实际 prefix-cache 命中率用于对比。 |
| `--log-dir` | 包含 UCM 日志文件的目录（递归扫描 `*.log`、`*.log.*`、`*.log.gz`）。必须包含 vLLM 启动日志（默认写到 `<UCM_LOG_PATH>/vllm-<pid>.log`），以便解析可用 KV cache 内存和 tensor-parallel 大小。 |
| `--block-kv-cache-size` | 单个 KV cache block 的大小（字节）。可用 [KV Cache Size Calculator](../getting-started/kv_cache_calculator.md) 根据模型确定。 |
| `--is-mla` | 是否为 Multi-Latent Attention 模型（`true`/`false`）。为 `true` 时 HBM 容量按单 rank 计算；否则按 tensor-parallel 大小相乘。 |
| `--dram-pool-size-gb` | 模拟 DRAM（主机内存）池大小，单位 GiB。 |
| `--fs-pool-size-gb` | 模拟文件系统（SSD/NFS）池大小，单位 GiB。 |

### 4.2 block-kv-cache-size 计算

`--block-kv-cache-size` 由模型架构决定。公式按单个 block 计算（**不除以 tensor-parallel**，是所有层/头的完整 block 大小）：

```text
GQA:          2 × num_hidden_layers × block_size × num_kv_heads × head_dim × dtype_bytes
MLA:          num_hidden_layers × block_size × (kv_lora_rank + qk_rope_head_dim) × dtype_bytes
DSA:          num_hidden_layers × block_size × (kv_lora_rank + qk_rope_head_dim + index_head_dim) × dtype_bytes
Hybrid (V4):  bytesPerToken × block_size
```

`--is-mla` 反映 KV 是否**跨 rank 共享**（压缩的 MLA/DSA/V4 KV 为 rank 共享 → `true`；GQA 按头分片 KV → `false`）。对应 UCM 的 `is_deepseek_mla` / `share_buffer_enable`（`ucm_connector.py:1063`、`ucm_connector.py:1251`）：为 `true` 时，从日志解析出的单 rank 可用 KV 内存已代表整个集群预算；否则乘以 tensor-parallel 大小。

以下取值假设 **bfloat16**（`dtype_bytes=2`）和 **`block_size=128`**（UCM 默认）：

| 模型 | Attention | `--is-mla` | `--block-kv-cache-size` |
| :--- | :--- | :--- | :--- |
| GLM-4.7 | GQA | `false` | `48234496` |
| GLM-4.7-Flash | MLA | `true` | `6930432` |
| GLM-5 / GLM-5.1 / GLM-5.2 | DSA | `true` | `14057472` |
| MiniMax-M2.7 | GQA | `false` | `32505856` |
| MiniMax-M3 | GQA | `false` | `15728640` |

**DeepSeek V4（hybrid）** 使用 `bytesPerToken × block_size`：

| 模型 | 部署 | `block_size` | bytesPerToken | `--is-mla` | `--block-kv-cache-size` |
| :--- | :--- | :--- | :--- | :--- | :--- |
| DeepSeek-V4-Pro | vllm-ascend | 32 | 27175 | `true` | `869600` |
| DeepSeek-V4-Pro | vllm-ascend | 128 | 27175 | `true` | `3478400` |
| DeepSeek-V4-Pro | vllm | 256 | 28415.4375 | `true` | `7274352` |
| DeepSeek-V4-Flash | vllm-ascend | 32 | 19162.5 | `true` | `613200` |
| DeepSeek-V4-Flash | vllm-ascend | 128 | 19162.5 | `true` | `2452800` |
| DeepSeek-V4-Flash | vllm | 256 | 20058.25 | `true` | `5134912` |

注意：

- fp16 保持相同值；fp8 减半；fp32 翻倍。
- `block_size` 必须与收集 trace 时使用的 vLLM `--block_size` 一致，否则推导出的容量与记录的 hash 对不上。
- 架构参数来源于 `docs/source/_static/model-configs.js`；DeepSeek V4 的 `bytesPerToken` 来自 `calculator.js`（`DEEPSEEK_V4_CONFIGS`）。请始终用 [KV Cache Size Calculator](../getting-started/kv_cache_calculator.md) 核对你的精确模型配置。

## 5. 结果解读

`print_summary` 将以下内容打印到 stdout（同样的值会写入 `--output` JSON 的 `analysis` 部分）。示例：

```text
Trace cache hit rate analysis
  Total request count: 1200
  Total request token count: 19660800
  Average tokens per request: 16384.00
  Total HBM available KV cache size: 12.50 GiB
  TP size: 2
  DRAM pool size: 64.00 GiB
  FS pool size: 1024.00 GiB
  Theoretical max KV cache hit rate: 78.340000%
  HBM theoretical hit rate: 21.560000%
  HBM + DRAM pool theoretical hit rate: 45.210000%
  HBM + DRAM pool + FS pool theoretical hit rate: 72.890000%
  Request lifetime sample count: 980
  Average request lifetime: 142.350000 s
  P90 request lifetime: 318.700000 s
  P95 request lifetime: 405.120000 s
```

### 工作负载与容量回声

确认日志解析与参数推导是否正确：

| 指标 | 含义 |
| :--- | :--- |
| `Total request count` | 解析到的 trace 记录数（= 请求数）。 |
| `Total request token count` | 所有请求 `input_length` 之和。 |
| `Average tokens per request` | 每请求平均输入 token 数。 |
| `Total HBM available KV cache size` | HBM KV 预算（GiB）。从 vLLM 的 `Current/Available KV cache memory` 解析；非 MLA 已乘以 `TP size`，MLA 为共享的单 rank 值。 |
| `TP size` | 从日志解析出的 tensor-parallel 大小。 |
| `DRAM pool size` / `FS pool size` | 传入的 `--dram-pool-size-gb` / `--fs-pool-size-gb`。 |

### 命中率场景

四组不同层级容量的 LRU 模拟，每个命中率都是 `hit_tokens / total_tokens`：

| 指标 | 使用的层级容量 | 说明 |
| :--- | :--- | :--- |
| `Theoretical max KV cache hit rate` | 每层 = `unique_block_count`（实际上限） | 上界，该流量下 UCM 可能达到的最大值。 |
| `HBM theoretical hit rate` | 仅 HBM（DRAM=FS=0） | 无外置池的基线，纯设备端 KV。 |
| `HBM + DRAM pool theoretical hit rate` | HBM + DRAM（FS=0） | 增加主机内存池带来的边际收益。 |
| `HBM + DRAM pool + FS pool theoretical hit rate` | 全部三层 | 最接近真实 UCM 部署的预期命中率。 |

按单调阶梯阅读：`HBM` ≤ `HBM+DRAM` ≤ `HBM+DRAM+FS` ≤ `Theoretical max`。关键点：

- **`Theoretical max`** 是该流量下的天花板。如果它本身很低，说明工作负载前缀复用少，无论如何扩大池子 UCM 都提升有限，此时可能不值得采纳 UCM。
- **`HBM`** 是无外置池基线。注意模拟值假设单请求在飞；真实**并发**下多请求会竞争 HBM KV 预算并互相驱逐，实际设备端命中率会**更低**。
- **`HBM + DRAM pool`** 是给定大小 DRAM 池可达成的值。与实时 `Service actual KV cache hit rate`（仅在配置 `--service-url` 时显示，取自 vLLM `/metrics`）相比，差值即 DRAM 池带来的提升。
- **`HBM + DRAM pool + FS pool`** 与 **`HBM + DRAM pool`** 之差为文件系统（SSD/NFS）层额外贡献的命中率。
- 若三层数值已接近 theoretical max，继续扩大 DRAM/FS 收益很小；若差距大，更大的池仍有帮助。

### 请求存活时间

衡量请求的 block 保持可复用时长（从任一 block 首次出现到最后一次被命中的时间跨度）：

| 指标 | 含义 |
| :--- | :--- |
| `Request lifetime sample count` | 至少有一个 block 被复用的请求组数量。 |
| `Average request lifetime` | 平均复用存活时长。 |
| `P90 request lifetime` | 90% 的被复用 block 在此窗口内再次被命中。 |
| `P95 request lifetime` | 95% 的被复用 block 在此窗口内再次被命中。 |

**`Average` / `P90` / `P95 request lifetime`** 是请求实际存活时间——从请求首次出现（对话开始）到其任一 block 最后一次被复用的跨度，衡量一段对话的 KV 能保持多久有用。用于确定保留窗口：例如 `P95 = 405 s` 表示 block 需在缓存中保留约 7 分钟才能捕获 95% 的复用——对照你的 DRAM/FS 容量与淘汰策略，即可判断池子是否够大、保留时间是否够长。