# mcp_flutter Fork：Release MCP 问题审查、修复计划与内嵌 WebView 支持设计

> 审查对象：[`maiji1990/mcp_flutter`](https://github.com/maiji1990/mcp_flutter)
> 基准提交：[`3d9234b`](https://github.com/maiji1990/mcp_flutter/commit/3d9234bacad984fc1349898b93ab834f1d34ea97)（2026-11-04）
> 上游：[`Arenukvern/mcp_flutter`](https://github.com/Arenukvern/mcp_flutter)
> 文档版本：2026-11-04 / **审查与方案，不代表修复已经合入**
> 建议仓库路径：`docs/release_runtime/security_review_and_webview_plan.md`

## 0. 执行摘要

Fork 已实现 Android Release 模式内置 MCP Server：`packages/release_runtime`（运行时、HTTP、权限、工具）与 `packages/release_runtime_flutter`（Flutter Semantics / 手势 / 截图适配），通过独立 Streamable HTTP 替代 Debug VM Service；仓库包含 Release Demo、HTTP/Widget 测试，并有 Android 17 实机验收记录。这不是从零开始的项目。当前工作应当是 **安全加固与 WebView 扩展**，不能仅凭现有 Demo 真机通过就宣称通用生产安全。

本审查依据 GitHub 源码的静态阅读与仓库中记录的测试结果；**没有在本次审查实际重新编译、运行 APK 或执行仓库测试**。下面区分“代码已确认的缺口”和“需要实验验证的风险”。

建议先做四项 P0：**敏感 UI 数据泄漏、权限撤销竞态、业务参数验证、截图默认安全策略**。然后做快照强一致性、会话隔离、Android 生命周期/CI。内嵌 `WebView` 需要独立 DOM Adapter：现有 Flutter Semantics 快照不能保证读取 HTML DOM。

## 1. 版本与现状

| 项目 | 本次确认 |
|---|---|
| Fork 默认分支 | `main`，基准 `3d9234b` |
| 上游差异 | 在本次检查时 Fork 领先 9 个提交、落后 0 个提交 |
| 核心包 | `flutter_mcp_toolkit_release` v0.6.0（`packages/release_runtime`） |
| Flutter 适配包 | `flutter_mcp_toolkit_release_flutter` v0.6.0（`packages/release_runtime_flutter`） |
| 已有工具 | `ui_get_tree`、`ui_get_current_page`、`ui_find_element`、`ui_click`、`ui_set_text`、`ui_scroll`、`app_invoke_action`、`ui_capture` |
| 协议 | `mcp_server` SDK 的 Streamable HTTP，Bearer Token、Origin 检查与会话机制 |
| 设备验证 | 仓库 `docs/release_runtime/android-deploy.md` 记载 Huawei PTP-AN10，Android 17/API 37，Release APK 真机通过；非本次重新复测 |
| 未覆盖 | 多 Android API 级别、不同厂商、后台/锁屏、旋转/分屏、多个同时操作的 Client 等 |

代码入口：[`release_runtime.dart`](https://github.com/maiji1990/mcp_flutter/blob/main/packages/release_runtime/lib/src/release_runtime.dart) 、[`http_transport.dart`](https://github.com/maiji1990/mcp_flutter/blob/main/packages/release_runtime/lib/src/server/http_transport.dart) 、[`flutter_ui_snapshot_source.dart`](https://github.com/maiji1990/mcp_flutter/blob/main/packages/release_runtime_flutter/lib/src/flutter_ui_snapshot_source.dart)。

## 2. 问题总表与修复优先级

> P0 = 正式接入真实业务数据前修复；P1 = 生产候选前修复/明确限用；P2 = 质量维护。风险排序是工程建议，非已证实的可利用漏洞评级。

| ID | 级别 | 问题/证据 | 处理方案 | 判定 |
|---|---|---|---|---|
| SEC-01 | **P0** | `RedactingPrivacyFilter` 仅遮盖敏感节点 `value`；`label`、`hint` 仍输出；其他普通 `Text` 节点不靠 `isObscured` 自动保护。Demo `/wallet` 含可见卡号文本，截图限制不能防止 `ui_get_tree` 输出。见 `privacy_filter.dart`、`showcase/flutter_release_demo/lib/main.dart` | 页面级只读策略 + `label/value/hint` 全字段脱敏 + 节点级 `sensitive`/排除策略；敏感页面默认拒绝读取 | **源码确认缺口** |
| AUTH-01 | **P0** | `_GuardedToolSurface.call()` 在进入 `_inner.call()` 前只检查一次权限；在队列中等待的业务操作有撤权竞态 | 统一操作调度器；执行前复检 `authorizationEpoch`、运行状态、client/session grant；排队任务撤权后拒绝，运行中按动作能力取消或声明无法回滚 | **源码确认风险** |
| ACT-01 | **P0** | `ReleaseAppAction.inputSchema` 已声明，但 `app_action_tools.dart` 内部将 `callArguments` 直接传 `handler`，未执行内部 Schema 验证 | 绑定 JSON Schema 验证器，输入不合法时拒绝；业务级鉴权、确认及幂等控制 | **源码确认缺口** |
| CAP-01 | **P0** | `ReleaseCapturePolicy.allowWhenRouteUnknown = true`、默认 `blockedRoutes = {}`，路由失败时可能放行截图 | 改为默认拒绝未知路由，支持 `allowedRoutes` 白名单；截图前后检查页面一致性；敏感页面无条件拒绝 | **源码确认风险** |
| UI-01 | P1 | `isSnapshotCurrent()` 主要比较 Semantics 快照计数；真实 UI rebuild、用户操作或 WebView 导航不一定改变计数器 | 增加真实 `uiEpoch`、routeId、控件 fingerprint；操作前验证节点属性和位置；返回 `stale_snapshot` | **需竞态/实机验证** |
| AUTH-02 | P1 | `_granted` 是 Runtime 全局集合，多个 MCP Client 共享同一套授权 | 加入 `clientId/sessionId`、设备配对、按会话授权/撤销；敏感操作绑定交互会话 | **源码确认设计局限** |
| UI-02 | P1 | `maxNodes` 限制在 `ReleaseReadTools` 读取后裁剪，`_findElement()` 调用全量 capture | 在 Semantics walk 源头下推限额及时间预算；避免大树构建；查询也限流 | **源码确认性能风险** |
| CAP-02 | P1 | 路由先读取、后截图；期间可能发生跳转 | 捕获后再次检查路由、navigationEpoch；不一致时丢弃整个 PNG | **需竞态/实机验证** |
| LIFE-01 | P1 | Demo 不具备系统后台/锁屏自动暂停控制器，当前验证文档明确未覆盖 | `WidgetsBindingObserver` + Activity lifecycle；非前台撤销可操作权限，停服或暂停；按厂商/API 测试 | **验证缺口** |
| NET-01 | P1 | `maxConcurrentRequests` 是配置字段，HTTP Transport 传递了会话上限，但未见独立请求并发队列绑定 | 为 Tool Dispatcher 添加并发上限、队列深度/超时和每会话配额；检查 SDK 能力后避免双重限流 | **需代码/压力测试确认** |
| CI-01 | P1 | 当前 `.github/workflows/` 中未见 `release_runtime` 独立必过工作流；本次获取不到当前主分支的成功 CI 运行记录 | 新增 CI job：`dart analyze`/`dart test`、`flutter test`、`flutter build apk --release`；增加测试矩阵 | **验证与门禁缺口** |
| DOC-01 | P2 | `docs/release_runtime/README.md` 仍写 PR-04 not started，安全文档含截图未实现/尚未真机测试等历史文本 | 同步状态与真实测试证据，注明版本、构建号、日期、环境 | **源码确认文档不一致** |
| META-01 | P2 | 两个新包 `pubspec.yaml` 的 `repository`、`issue_tracker` 指向原作者仓库 | 修改为 `maiji1990/mcp_flutter` 的 Fork 地址；保留 MIT 版权与原作者归属 | **源码确认元数据问题** |
| TEST-01 | P2 | Demo 将 Bearer token 直接展示在界面 | 仅 Demo 允许；生产版采用用户主动配对展示、短期 Token、界面录屏风险提示；测试误曝光 | **生产接入注意事项** |

### 2.1 SEC-01：UI 隐私策略

相关源码：
- [`packages/release_runtime/lib/src/privacy/privacy_filter.dart`](https://github.com/maiji1990/mcp_flutter/blob/main/packages/release_runtime/lib/src/privacy/privacy_filter.dart)
- [`packages/release_runtime_flutter/lib/src/flutter_ui_snapshot_source.dart`](https://github.com/maiji1990/mcp_flutter/blob/main/packages/release_runtime_flutter/lib/src/flutter_ui_snapshot_source.dart)
- [`showcase/flutter_release_demo/lib/main.dart`](https://github.com/maiji1990/mcp_flutter/blob/main/showcase/flutter_release_demo/lib/main.dart)

**方案**：设计 `ReleaseUiPrivacyPolicy`，按页面（route）、组件（identifier）、语义节点属性和数据类别确定 `deny/mask/allow`。默认规则：`sensitive` 节点的 `label`、`value`、`hint`、扩展 metadata 统一遮盖；敏感页面即使 `ui:read` 已授权仍拒绝；高敏感页面由 App 显式允许某些安全节点（白名单）才输出。仅截断不是脱敏。可提供 `AgentSensitive` / `ExcludeFromAgent` Flutter Wrapper 或路由策略声明；避免要求用户只能通过 `obscureText` 标识敏感数据。

**验收**：将示例钱包页 `Card number 4111 1111 1111 1111` 作为回归样本；`ui_get_tree`、`ui_find_element`、异常返回、事件消息中均不得包含卡号。包含敏感 `label`、`hint`、自定义绘制文字/控件的案例分别测试。

### 2.2 AUTH-01：撤权、停服与排队动作

相关源码：[`release_runtime.dart`](https://github.com/maiji1990/mcp_flutter/blob/main/packages/release_runtime/lib/src/release_runtime.dart)、[`interaction_tools.dart`](https://github.com/maiji1990/mcp_flutter/blob/main/packages/release_runtime/lib/src/tools/interaction_tools.dart)、[`app_action_tools.dart`](https://github.com/maiji1990/mcp_flutter/blob/main/packages/release_runtime/lib/src/actions/app_action_tools.dart)。

**方案**：
1. `grant/revoke/stop` 都递增 `authorizationEpoch`；操作请求在入队时记录 `clientId`、所需权限与 epoch。
2. 派发真实 UI 操作或业务 Handler **紧前**再次检查运行状态、权限和 epoch（不能只在 HTTP 层查一次）。
3. `stop()` 标记 `stopping` 后立即拒绝新任务，尽可能取消排队任务；已不可取消的业务动作返回准确的“已开始/已提交”状态，不声称回滚成功。
4. 操作队列与应用业务动作共用一致的授权执行边界；可定义取消令牌与超时。

**验收**：A 任务阻塞 → B 排队 → 用户撤销 `ui:interact` / `app:...` → 放行 A；B 必须被拒绝，且业务计数不变化。重复执行 `stop/restart` 后旧授权不得残留。

### 2.3 ACT-01：严格校验业务动作

相关源码：[`app_action.dart`](https://github.com/maiji1990/mcp_flutter/blob/main/packages/release_runtime/lib/src/actions/app_action.dart)、[`app_action_tools.dart`](https://github.com/maiji1990/mcp_flutter/blob/main/packages/release_runtime/lib/src/actions/app_action_tools.dart)。

**方案**：使用受维护的 JSON Schema 解析/验证实现，注册时校验 Schema 自身，调用时验证 `arguments`（类型、必填、最大长度、枚举、`additionalProperties:false`、嵌套对象和数组）；失败返回 `invalid_argument`，Handler 不被调用。高风险业务动作额外要求用户确认、业务服务端权限检查、幂等键。

**验收**：传入超长字符串、缺失字段、错误类型、额外字段、深层对象等均拒绝；合法输入成功。禁止利用 Action 绕过 App 的原有业务权限。

### 2.4 CAP-01 / CAP-02：截图默认拒绝

相关源码：[`capture_policy.dart`](https://github.com/maiji1990/mcp_flutter/blob/main/packages/release_runtime/lib/src/capture/capture_policy.dart)、[`capture_tools.dart`](https://github.com/maiji1990/mcp_flutter/blob/main/packages/release_runtime/lib/src/tools/capture_tools.dart)。

**方案**：`allowWhenRouteUnknown: false`；新增 `allowedRoutes`，默认空（即默认不可截图，需 App 开放）；捕获前后比较 route、navigationEpoch 和敏感状态；路由变更则丢弃图像。截屏禁止策略必须同时对 Flutter UI 与嵌入的 WebView 生效。

**验收**：未知路由、被屏蔽路由、截图期间导航跳转均拒绝，不发送任何 `bytesBase64`。明确说明 Flutter `RenderView` 截屏对 Android Platform Views 可能不完整。

### 2.5 UI-01 / AUTH-02：快照与 Client 隔离

- 快照 ID 不等价于 UI 状态指纹。快照引用建议绑定 `{clientId, viewId, routeEpoch, semanticEpoch, snapshotNonce}`，而非全局递增计数器单独判断。
- 节点操作前重新验证：`identifier`、`type`、`enabled`、`actions`、几何位置/可见性与路由；必要时重新采样目标节点。
- 多个客户端需各自持有最近的快照、权限与上限；禁止客户端 A 的 Ref 被客户端 B 直接复用或导致不必要的相互失效。全局写操作可串行，但授权必须会话隔离。

**验收**：用户手动切页后旧 Ref 不能点击新页面；两个 Client 并发读取/操作时互不越权；在途任务撤权必须拒绝。

### 2.6 LIFE / CI / DOC：工程收尾

- Android：前后台/锁屏/屏幕旋转/分屏/进程恢复需明确策略，`WidgetsBindingObserver` 和 Activity 生命周期测试；不要将普通 Dart HttpServer 假设为后台常驻服务。
- CI：新增独立 `release_runtime.yml`，两个包的静态分析和测试、Release APK 构建为必过门禁；按最低目标 Android API、主流机型扩充实机矩阵。
- Docs：更新 README/安全说明中过时状态；新增 `CHANGELOG` 与真实设备证据表。更正 Fork 包元信息，不改写上游版权。

## 3. 内嵌 WebView：当前能力判断

**结论：可以扩展支持，但不能指望当前 `FlutterReleaseUiSnapshotSource` 自动取到 WebView 里的 DOM。**

- Flutter `WebViewWidget` 在 Android 上承载原生 WebView Platform View；Flutter Semantics 与浏览器 DOM 是两套不同的树。现有快照最多能识别宿主组件/部分可访问语义，不能保证列出 `button/input/div/table`。
- 官方 `webview_flutter` 提供 `WebViewController.runJavaScriptReturningResult()`，宿主应用可以在**已授权、受信任**页面中查询实际 DOM；无需 VM Service，Release APK 可以使用。
- JS 可以读取网页主文档的当前已渲染内容；同源 iframe 需单独遍历，跨源 iframe 受同源策略限制；Canvas/WebGL、原生播放器等没有对应的 HTML 语义树。
- 当前截图通过 `RenderView` 图层导出，不保证组合了 Android Platform View 像素。WebView 截图需要独立设备验证，必要时走受控原生捕获通道。

官方参考：
- [Flutter WebView API（runJavaScriptReturningResult）](https://github.com/flutter/packages/blob/main/packages/webview_flutter/webview_flutter/lib/src/webview_controller.dart)
- [Flutter Android Platform Views](https://github.com/flutter/flutter/blob/master/docs/platforms/android/Android-Platform-Views.md)
- [Android WebView evaluateJavascript / native bridge](https://developer.android.com/reference/android/webkit/WebView)
- [Android 官方 WebView native bridge 安全指南](https://developer.android.com/privacy-and-security/risks/insecure-webview-native-bridges)
- [MDN 同源策略](https://developer.mozilla.org/en-US/docs/Web/Security/Defenses/Same-origin_policy)

### 3.1 可支持与不可保证的范围

| 场景 | 方案 | 限制 |
|---|---|---|
| App 内自有 H5（Vue/React/普通 HTML） | WebViewController + DOM Adapter | 获取当前 DOM，不保证虚拟列表未挂载元素 |
| WebView 内按钮、表单、列表 | DOM Snapshot + 受控 DOM Action | `.click()` 触发的事件不一定具有真实用户事件的 `isTrusted` |
| 同源 iframe | 在浏览器同源限制允许时遍历 | 需明确嵌套限制/独立 frame ID |
| 跨源 iframe | 主页面通常只能给出 iframe 元数据 | 不尝试绕过同源策略 |
| Canvas、WebGL、视频画面 | 截屏辅助 / App 自定义可观察接口 | DOM 无法反映实际绘图内容 |
| 其他 App 内的 WebView | 不在本 Fork 的普通 MCP 权限范围 | 必须另设计 Android AccessibilityService，且用户授权 |
| Flutter Web（运行于浏览器的 Flutter App） | 与 Android WebView 是不同目标 | 需要专门 Web 平台适配，非本次任务 |

## 4. WebView 新增补丁设计（建议 v0.7.0）

### 4.1 包与目录选择

保持两个现有 Release 包不强制依赖 WebView 插件，新增**可选**的 Provider 包：

```text
packages/
  release_runtime/                     # 已有：MCP、权限、Tool 定义
    lib/src/web/                       # 新增：抽象契约、Web 工具/权限
  release_runtime_flutter/             # 已有：Flutter Semantics 与手势
  release_runtime_webview/             # 新增：可选适配包
    lib/flutter_mcp_toolkit_release_webview.dart
    lib/src/webview_registry.dart
    lib/src/webview_flutter_adapter.dart
    lib/src/dom_snapshot_script.dart
    lib/src/dom_action_script.dart
    lib/src/dom_privacy_policy.dart
    lib/src/navigation_epoch.dart
    test/
showcase/flutter_release_demo/
  lib/web_demo/                          # 新增：内嵌受控测试 H5
```

先支持官方 `webview_flutter`，以后通过适配器接口接入 `flutter_inappwebview`，避免硬绑定某个控件实现。不要自动扫描整个 Widget Tree 寻找控制器；由宿主应用显式注册允许智能体读取的 WebView。

### 4.2 跨界面统一抽象

建议新增这些协议概念（**接口草案，尚未实现**）：

```dart
abstract interface class ReleaseEmbeddedWebSource {
  Future<WebDomSnapshot> capture({required String viewId, int maxNodes = 200});
  Future<WebDomActionResult> click({required WebTargetRef target});
  Future<WebDomActionResult> setText({required WebTargetRef target, required String text});
  Future<WebDomActionResult> scroll({required WebTargetRef target, required double dy});
}

// App 只注册自己控制的 WebView：
// registry.register(viewId: 'order-h5', controller: webViewController,
//   allowedOrigins: {'https://app.example.com'}, policy: pagePolicy);
```

MCP Tool 建议：

| Tool | 参数（核心） | 权限 |
|---|---|---|
| `web_list_views` | 无；只返回 App 已注册的 View | `web:read` |
| `web_get_tree` | `viewId`, `maxNodes`, `maxDepth` | `web:read` |
| `web_find_element` | `viewId`, `identifier/role/text` | `web:read` |
| `web_click` | `viewId`, `ref`, `snapshotId` | `web:interact` |
| `web_set_text` | `viewId`, `ref`, `snapshotId`, `text` | `web:interact` |
| `web_scroll` | `viewId`, `ref`, `snapshotId`, `direction/amount` | `web:interact` |
| `web_get_state` | `viewId`；只返回受控加载状态和安全 URL 元数据 | `web:read` |

不要把 `web_evaluate_javascript(script)` 作为普通 MCP 工具暴露给 Agent：这会把页面数据、登录态与 JS 执行权限直接交给外部客户端，超出最小权限原则。只有插件内部固定脚本，接收经过 Schema 验证的有限参数。

V1 可先独立提供 `web_*` 工具；等测试完善后再将 WebView 节点并入 `ui_get_tree`，统一包装 `{source:'flutter'|'webview', viewId, ref, snapshotId}`，保证原有 `ui_*` 客户端兼容。

### 4.3 DOM 快照算法

1. App 注册 `viewId` + `WebViewController` + 允许的 HTTPS Origin 列表（**精确匹配 scheme/host/port**）。
2. 调用前查询当前 URL、导航状态；拒绝未授权来源。对于异步执行，脚本内部再核验 `location.origin`，返回时再次检查导航 epoch。
3. 固定 JS 遍历 `button, a, input, textarea, select, [role], [tabindex]` 等可操作元素，并按需补充可见文本节点（受预算限制）。
4. 优先读取 `aria-label`、`role`、安全文本、`disabled`、`checked`、`getBoundingClientRect()`；不读取 `input[type=password]` 值、Cookie、LocalStorage、Token、表单自动补全敏感值及完整 HTML 源码。
5. 对 `input` 的值执行敏感字段规则；对于自由文本与金融/个人信息页面，先经过 URL/route 白名单，必要时整页拒绝。
6. 为当前视图生成 `web:<viewId>:<navigationEpoch>:<snapshotNonce>:<ordinal>` 临时 Ref；不要把 CSS selector 当成永久标识，不要将敏感内容拼入 Ref。
7. 在执行点击/输入前校验原页面、导航 epoch、DOM 版本、目标角色及可见性；动作后再采样以验证效果。

JS 读取示例（**仅展示思路；需加入上限、权限和异常处理才能用于生产**）：

```javascript
(() => {
  const allowed = new Set(['https://app.example.com']);
  if (!allowed.has(location.origin)) return JSON.stringify({ error: 'origin_denied' });
  const nodes = Array.from(document.querySelectorAll(
    'button,a,input,textarea,select,[role],[tabindex]'
  )).slice(0, 200).map((el, i) => {
    const r = el.getBoundingClientRect();
    const secret = el.matches('input[type=password],[data-agent-sensitive]');
    return {
      ref: `dom_${i}`,
      tag: el.tagName.toLowerCase(),
      role: el.getAttribute('role'),
      label: secret ? '[REDACTED]' : (el.getAttribute('aria-label') || '').slice(0, 100),
      text: secret ? '[REDACTED]' : (el.textContent || '').trim().slice(0, 100),
      rect: { x: r.x, y: r.y, width: r.width, height: r.height },
      disabled: Boolean(el.disabled)
    };
  });
  return JSON.stringify({ origin: location.origin, nodes });
})()
```

以上示例不应原样用于完整采集（例如 `textContent` 可能包含隐藏后代文本，需要改成仅可见语义文本并进行页面级隐私处理；普通 DOM 文本也可能涉及个人数据）。返回值经 Dart 端 `runJavaScriptReturningResult()` 处理时需兼容不同平台返回 `String` / 基本类型，并为 JS 执行设定超时、页面状态校验和大小上限。

### 4.4 WebView 事件、截图、坐标

- 监听页面开始/完成和 SPA History API 导航，推进 `navigationEpoch`；按需在允许的自有页面安装轻量 `MutationObserver`，推进 DOM 变更版本，防止旧引用误操作。单靠 `onPageFinished` 不足以跟踪 SPA 的每次局部更新。
- WebView 返回的元素矩形是**网页 viewport 的 CSS 像素**，而 Flutter 是逻辑像素；如需跨层坐标点击，必须转换 WebView 宿主位置、滚动、缩放、设备像素比，并保证 hit-test 实际命中。首版优先 DOM 动作而非坐标。
- `.click()` / 脚本赋值可能遭网站限制，且不保证生成受信任用户交互；登录、支付、第三方页面需人工介入或使用 App 已授权业务 API。
- Android Platform View 的截图不要只依赖 `RenderView` 导出；需要实机比对 `ui_capture` 是否包含 WebView。若无，选择有权限的原生 WebView/窗口捕获实现，或明确返回 `platform_view_capture_unavailable`，不谎报为完整屏幕。

### 4.5 WebView 安全边界（必须）

- WebView 只能由宿主 App 显式注册；默认所有视图不可访问；禁止插件静默开启页面 JavaScript 功能。若页面需 JS，则需 App 同意并明确适用范围。
- 只允许可信 HTTPS Origin；跨域跳转立即暂停采集/操作。拒绝 `file://`、`content://`、`javascript:`、`data:` 等不受控上下文，除非 App 定义专门的安全策略。
- 不向 Agent 开放任意 JS 执行，不通过 MCP 返回 Cookie、Storage、完整 DOM/HTML、授权头、密码/OTP、未裁剪 URL 查询参数。
- **尽量避免 `addJavascriptInterface`**：Android 文档指出原生桥可能暴露给所有 frames，并有来源验证风险；采用宿主主动调用 `runJavaScriptReturningResult()` 读取有限结果即可。若必须双向推送，严格做来源控制和消息 Schema 验证。
- 页面显示的文本是不可信数据：Agent 不得把网页文字当作工具授权或系统指令；Tool 输出仅作为数据，并进行提示注入防护。
- WebView 操作权限独立于 Flutter `ui:interact`；重要动作还须 App 业务层确认。

## 5. 迭代安排及验收

### v0.6.1 — Release 安全加固（先于 WebView）

| PR | 工作 | 通过条件 |
|---|---|---|
| PR-07 | 全字段隐私策略与路由级读取限制 | 钱包页文本、敏感 label/hint 不泄漏 |
| PR-08 | 授权 epoch / 排队任务撤权 / Stop 取消规则 | 撤权与停服后不执行待派发动作 |
| PR-09 | Action 参数 Schema、截图白名单与导航复验 | 非法参数拒绝；未知路由不截图 |
| PR-10 | UI 版本一致性、并发/多会话检查、CI、文档 | 旧 Ref 拒绝、CI 全绿、至少一台真机回归 |

### v0.7.0 — 内嵌 WebView 能力

| PR | 工作 | 通过条件 |
|---|---|---|
| PR-W01 | 可选 WebView Adapter 包与显式控制器注册 | 已注册、可信 URL 的 WebView 可被识别；其他不可见 |
| PR-W02 | `web_get_tree` / `web_find_element` + 隐私过滤 | Release APK 能读取自有 H5 可见 DOM，无敏感数据 |
| PR-W03 | `web_click` / `web_set_text` / `web_scroll` + epoch/ref 校验 | 按钮、表单、长列表可操作；导航后旧 Ref 被拒绝 |
| PR-W04 | Hybrid 截图验证、SPA/iframe 测试和文档 | 不完整截图有准确错误；跨域 iframe 被隔离 |

**完整验收场景**：Flutter 首页 → 打开 App 自己托管的订单 H5 → Agent 读取网页按钮/输入框 → 填写非敏感搜索字段 → 点击查询 → DOM 变化 → Agent 重新采样并验证结果 → 用户撤销权限 → 后续操作拒绝。

## 6. 建议给 Codex 的工作指令

```text
目标仓库：maiji1990/mcp_flutter
基准：main @ 3d9234b（开始前先 fetch 核验最新分支）
只向我的 Fork 提交，不向 Arenukvern/mcp_flutter 提交 PR。

任务分两个阶段：
A. 首先按 docs/release_runtime/security_review_and_webview_plan.md 完成 v0.6.1 的安全加固，优先处理 SEC-01、AUTH-01、ACT-01、CAP-01；每项必须有可复现的失败测试与修复后的通过测试。
B. 再在独立可选包中完成 Android WebView Release DOM Adapter；不得向外部 MCP 客户端开放任意 JavaScript 执行；必须有页面来源白名单、节点脱敏、导航版本校验、独立 web:read/web:interact 权限。

保持现有 Debug MCP/CLI/Harness 行为不变，减少修改上游原文件；使用 Flutter 3.47+/Dart 3.13 环境验证，运行静态分析、单元测试、Widget/HTTP 测试和 Release APK 实机演示。
提供每个 PR 的变更清单、测试结果、限制及未修复风险。不要把 README 中记录的测试当作本次实际执行结果。
```

## 7. 本次审查的限制

- 审查读取的是公开的 GitHub `main` 源码；提交后有变更则需重新对照。
- 本次没有本地编译/ADB 真机，也未执行安全扫描或渗透测试；不能声称已证明某漏洞可被外部利用。
- WebView 能力属于**设计提案**，并非 Fork 现有已完成功能。
- 新版 API 的具体签名应以安装的 Flutter/WebView/MCP SDK 为准，代码示例是工程骨架而非可直接发布的完整实现。
