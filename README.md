# AUREL

Private Capital Desk：一款只读行情、资产数据留在本机的原生 macOS 个人理财工作台。

## 数据纪律

- 资产、现金和事件写入 `~/Library/Application Support/WealthWorkbench/portfolio.json`。
- Twelve Data API Key 保存在应用专属本地文件，文件权限为 `0600`，不读取或写入钥匙串。
- AUREL Desk 可选择 OpenAI `gpt-5.6-sol` 或 SpaceXAI `grok-4.6`。OpenAI 的完整 Responses 访问地址与 API Key 成对写入 `openai-credentials.json`，SpaceXAI 与 Twelve Data Key 分别写入独立本地文件；全部位于 `~/Library/Application Support/WealthWorkbench/Credentials/`，权限 `0600`，重启自动恢复，不读取或写入钥匙串，也不会进入仓库。发送对话时会把当前持仓快照传给所选服务，原始资产文件仍只保存在本机。
- 行情优先级为 Futu OpenD、Twelve Data、腾讯公开备用行情；备用行情始终标注“可能延迟”。
- 每条价格附带市场、币种、价格类型、交易时段、比较基准、行情时间、抓取时间、来源和延迟状态。
- 请求失败或字段不可验证时显示“暂无数据”，刷新前会清空旧行情。
- 美股盘前、常规、盘后和夜盘分别使用对应字段；公开源无法证明扩展时段时只显示今日或最近收盘，不冒充扩展时段价。
- 事件日历通过 Futu OpenD 官方只读接口获取未来 7 日中高影响经济事件，并按本地持仓筛选财报日历；只给日期的财报事件会标注“时间待定”。
- 金十不使用网页抓取或已停止的免费引用接口；只有取得开放平台正式授权后才会接入。
- 财经资讯在应用启动后后台预取；12 小时内的成功缓存会先展示并明确标注缓存时间，更新失败时不会清空当前阅读列表。
- 右下角悬浮 AUREL Desk 是只读投资助手：用本机持仓、行情护照、事件和资讯标题做研究，缺数就写「暂无数据」，不编造价格，也不下单。回复中的 Markdown 标题、要点与数据表会分别渲染，宽表可横向滚动。快捷键 `⌘L`。
- 助手技能从公开投研框架蒸馏而来，全部改成只读、可在无完整财报时降级：AI Berkshire（组合/清单/去劣/财报/新闻/论文/瓶颈）、[InvestSkill](https://github.com/yennanliu/InvestSkill)（Piotroski/ROIC、DCF、空方红队）、[trading-skills](https://github.com/marian2js/trading-skills)（组合风险、仓位规模、决策前检、宏观传导、财报前瞻）、[Peter Lynch skill](https://github.com/DjNero11/peter-lynch-skill)、[equity-research-skill](https://github.com/rollingSirius/equity-research-skill)（预期差）、[Day1Global-Skills](https://github.com/star23/Day1Global-Skills)（四维价值与流动性口径）。不接入交易接口，不把训练记忆当成最新报表。

## 官方契约

- [Apple NavigationSplitView](https://developer.apple.com/documentation/swiftui/navigationsplitview)
- [Futu 获取快照](https://openapi.futunn.com/futu-api-doc/en/quote/get-market-snapshot.html)
- [Futu 获取市场状态](https://openapi.futunn.com/futu-api-doc/quote/get-market-state.html)
- [Futu 经济日历](https://openapi.futunn.com/futu-api-doc/hk/quote/get-economic-calendar.html)
- [Futu 财报日历](https://openapi.futunn.com/futu-api-doc/en/quote/get-earnings-calendar.html)
- [金十开放平台](https://open.jin10.com/document?anchor=flash-10102-intro)
- [Twelve Data 扩展时段](https://support.twelvedata.com/en/articles/5195429-pre-post-market-data)
- [Frankfurter 汇率 API](https://frankfurter.dev/)
- [OpenAI GPT-5.6-sol](https://developers.openai.com/api/docs/models/gpt-5.6-sol)
- [OpenAI Responses API](https://developers.openai.com/api/reference/resources/responses/methods/create)

## 本地验证

项目在没有完整 Xcode、只有 Command Line Tools 的 Mac 上使用独立校验程序。它覆盖数量反推、时段分类、跨日保护、公开行情解析、失效降级、持久化和汇率换算。

发布构建由 `scripts/build-release.sh` 完成，产物位于 `dist/`。
