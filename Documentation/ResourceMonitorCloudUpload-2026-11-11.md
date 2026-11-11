# 中国移动云盘上传时，Resource Monitor 为什么漏流量

调查日期：2026-11-11。调查期间沿用用户正在进行的上传，没有暂停、重新发起或修改上传任务。Resource Monitor 使用 bytes 单位和 2 秒刷新周期。

## 已证实的原因

**旧 helper 把 nettop 的当前进程汇总当作只增不减的累计计数。上传连接结束后，汇总里对应连接的历史字节会消失，导致总量下降；旧代码遇到下降就记为 0，因此持续漏掉真实上传流量。**

本次实际上传进程为 **uploadDownload，PID 32834**，属于中国移动云盘。它有多条连接指向云盘服务器，nettop 标记为 **en0**。external 筛选能够读到这些连接。

一次完整连接明细快照还验证了汇总的来源：10 条远端 TCP 连接的上传字节合计 **31,498,677**，本机回环连接为 **181,612**，进程汇总为 **31,680,289**，恰好等于前两者相加。这组快照没有筛掉回环，仅用于核对汇总含义，未用于网络速率基准。它证实进程行汇总的是当时列出的连接字节，而不是独立保存的一份进程终身累计值。

初次界面对照中，云盘显示 **4.33 MB/s**，Resource Monitor 显示 **1.827 MB/s**。连续 nettop 增量采样确认当时确实每秒上传约 4–5 MB，因此不是只看到了云盘界面上的虚高数字。

## 具体在哪里漏算

调用链为：

**TrafficMonitor.launchHelper → net-speed-all 的 emit → networkCounters → 每次新启动一次 nettop，读取当前进程汇总 → 与上次汇总相减。**

修复前，Upstream/ResourceMonitor/Sources/NetSpeedHelper/main.swift 的 **emit** 第 188–196 行包含以下逻辑：

```swift
guard let previous = previousNetwork[process] else { continue }
let upload = current.upload >= previous.upload
    ? current.upload - previous.upload
    : 0
externalUpload += upload
```

实际捕获到的一组数值：

| 项目 | 实际值 |
|---|---:|
| 进程 | uploadDownload.32834 |
| 上次进程汇总上传字节 | 33,566,902 |
| 本次进程汇总上传字节 | 20,724,997 |
| 两次采样实际间隔 | 2.094994458 秒 |
| 旧代码给这个进程记入的上传增量 | 0 |
| 该轮 helper 全机上传输出 | 25,425 bytes/s |

计数值来自临时观测的原始进程行；0 的贡献由这些数值与当时的分支计算共同证实。这组记录位于首次观测的第 60–61 条记录。

首次 32 秒观测捕获了 **7 次** uploadDownload 上传汇总下降。即使总量没有下降，相减也只得到“新发送字节减去已退出连接的历史字节”，仍可能少算。因此仅把负值改成另一个数，不能补回真实流量。

## 同一笔上传的修复前后对照

每轮比较约 32 秒，排除启动后的前 8 秒。helper 使用 2 秒刷新；独立 nettop 使用 1 秒连续增量，第一帧的已有总量排除。MB/s 在下表中统一为 1,000,000 bytes/s。

| 对照轮次 | 原版 helper 平均 MB/s | 修复候选 helper 平均 MB/s | uploadDownload 连续增量平均 MB/s |
|---|---:|---:|---:|
| 修复前，候选仅添加观测代码 | 1.428169 | 1.423452 | 4.562921 |
| 修复后，保留观测代码验证 | 1.200181 | 4.649124 | 4.610039 |
| 移除观测代码后的 Release 构建 | 1.038745 | 4.821729 | 4.637671 |

第一轮原版读数约为实际云盘进程上传的 **31.3%**，在这一时间段约漏了 **68.7%**。缺失比例会随连接关闭的时间变化，不是固定乘法系数。

第二轮修复候选与独立参考相差约 **0.85%**。Release 轮次约相差 **3.97%**。候选统计全机 external 流量，而独立参考只统计 uploadDownload；采样时点也有小幅差异，因此这些差值不能直接当作精确误差率。两轮修复后的结果均恢复至真实上传量级。

参考数据量：

| 轮次 | 原版 helper 稳定段样本数 | 候选稳定段样本数 | 独立参考样本数 |
|---|---:|---:|---:|
| 修复前 | 12 | 12 | 24 |
| 修复后 | 12 | 12 | 24 |
| Release 构建 | 12 | 12 | 24 |

调查后段另一次界面观察中，云盘显示 **2.50 MB/s**，当前安装的旧 Resource Monitor 显示 **85.28 KB/s**。这两次界面读取相差几秒，仅用于确认漏算症状仍在旧版出现，不用于计算精确缺失比例。

## 代码如何修复

网络侧保留一个连续运行的 **nettop -P -d -t external -L 0 -s 1**，直接消费 nettop 自己维护的增量。已有的 helper 定时循环将这些增量累计后，按实际经过时间换算速率。

具体处理：

- **NetworkDeltaParser** 排除第一帧已有累计值，后续每个进程行只累加一次。新进程和关闭连接不会触发“与旧进程总量相减”的路径。
- parser 保留未读完的行，支持一个 CSV 行分成多次读取，以及一次读取包含多帧。
- 使用 PTY 输出，让 nettop 每帧及时刷新。实验确认普通 pipe 的小量输出会滞留在缓冲区；PTY 每秒收到一帧。
- 用系统 **read** 读取已经到达的字节，避免等待一个固定大小的读取缓冲填满。
- 采集进程退出时 helper 自己退出，交给主应用已有的重启机制恢复。
- 宿主发送 SIGTERM 结束 helper 时，helper 先终止并回收 nettop。Foundation 会给子进程单独的进程组，不能仅靠结束 helper 的进程组清理采集器。

磁盘、CPU、内存的计数逻辑和界面单位换算未修改。

最终源码位置：

| 内容 | 位置 |
|---|---|
| 首帧排除与 CSV 增量解析 | Upstream/ResourceMonitor/Sources/NetSpeedHelper/main.swift，NetworkDeltaParser，20–49 行 |
| 持续采集、PTY 和增量累计 | 同文件，ExternalNetworkSampler，51 行起 |
| 取走本轮增量 | 同文件，takeCounters，102–109 行 |
| 换算网络速率 | 同文件，emit |
| 启动采集器、处理 SIGTERM、进入原有定时循环 | 同文件，setpgid 之后的启动代码 |
| 回归测试 | Upstream/ResourceMonitor/Tests/NetworkDeltaParserTests.swift |
| 单独运行这些测试 | python3 Scripts/test-resource-network-helper.py |

## 验证结果

- parser 回归测试通过：启动时不计入历史总量；增量数值变小仍正常累加；新进程即刻计入；进程退出不抹去其他进程流量；UTF-8 名称、CRLF、多个帧和 1/2/7/64 字节分段均正确；无效数字和未完成行不误计、不重放。
- 已将测试加入 **Scripts/test-all.sh**，本次单独运行了新增测试，没有运行与此次修改无关的整个模块测试套件。
- Release helper 的 arm64、x86_64 构建成功，严格签名验证通过。真实上传验证在本机原生架构运行。
- 实际终止新 helper 自己的 nettop 子进程后，helper 按预期以状态 1 退出，可由原有宿主监督机制重新拉起。没有终止用户上传进程或当前安装的 Resource Monitor。
- 实际向测试 helper 的进程组发送 SIGTERM 后，helper 按预期以状态 0 退出，nettop 子进程已被回收。采集器先退出和 helper 先退出两种测试均已加入自动测试脚本。
- 移除临时观测代码后的正式构建再次通过真实上传对照。

## 证据结论

progress_status：verified。

| 假设 | 结果 | 证据 |
|---|---|---|
| A：external 筛选排除了主要上传连接 | REJECTED，本次连接范围内 | uploadDownload 的实际连接标记为 en0；external 连续增量约 4.563 MB/s |
| B：汇总计数回退后被记成 0，导致漏算 | CONFIRMED | 明确的回退数值、旧 helper 错误输出及修复后量级恢复 |
| C：云盘仅展示秒传或本地处理速度 | REJECTED，作为本次缺口的解释 | 持续 TCP 上传与连续增量证实真实网络发送 |
| D：helper 正常但界面更新不及时 | REJECTED，作为本次主因 | 原版 helper 的 JSON 本身就低到约 1.428 MB/s，缺失发生在显示之前 |

原始证据包括：云盘与 Resource Monitor 的现场界面、进程和连接信息、nettop 当前汇总与连续增量、原版 helper JSON、临时观测及修复后的 JSON。初次未及时刷新到 pipe 的参考轮次，以及首次流读取显示 0 的候选轮次，均未作为成功验证依据。

## 对上一份报告的修正与当前安装状态

先前受控 curl 上传/下载经过 corplink，未暴露本次云盘进程汇总回退造成的漏算。因此先前“受控测试没有固定翻倍/减半”的结果，不能推导为“工具对所有应用的流量都准确”。本次明确证实旧版网络采样有缺陷；先前的磁盘对照结果不受该缺陷影响。

调查结束时仅修复了源码，安装的应用仍是旧版。随后按用户要求，已更新 **/Applications/MyMacSwissArmyknife.app 至 1.0 build 44** 并重新启动。

安装后的核验：

- 主应用与 Finder 扩展的 CFBundleVersion 均为 44，完整签名校验通过，Finder 扩展仍处于启用状态。
- ResourceMonitor 运行进程为 56856，helper 为 56872，其连续 nettop 子进程为 56873。
- 安装的 helper 与本次 Release 构建完全一致，SHA-256：**8dfcf26288e352e5c296c007ca813bb89f65a07b688445d756b283aae7f12bc9**。
- 实际界面已显示 **4.520 MB/s** 上传。该值包含全机流量，并非单独某个云盘任务的速率。
- bytes 单位、2 秒刷新、悬浮窗、菜单栏及各项指标开关均保留。云盘传输进程 32834 在更新前后保持运行。
- 旧安装包备份位于 **~/Library/Application Support/MyMacSwissArmyknife/Backups/MyMacSwissArmyknife-build43-before-network-fix-20261111.zip**。
- 新的完整本地安装包：**Build/Release/MyMacSwissArmyknife-v1.0-build44.zip**。
- 安装包 SHA-256：**cc0d1707977f9baa4efc3d0aa1c6af0b302487ae498b476948adff83cc850f3a**。

调查和安装阶段未创建提交或向远端发布版本。临时日志、调查记录、测试程序、测试构建和采集服务在整理结果后清理；保留源码修复、测试、调查报告和本地安装包。
