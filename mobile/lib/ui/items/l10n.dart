// The phone's strings for the ported chat items: the desktop's
// `context.l10n` (`lib/l10n/`, generated from app_*.arb) reduced to the
// keys the item widgets read, in Chinese — the phone's only language.
import 'package:flutter/widgets.dart';

/// The keys the chat items read, as the desktop's `AppLocalizations`
/// gives them in Chinese.
class L10n {
  const L10n();

  // Activity row (the "…" line while the agent works).

  String get activityCompacting => '正在压缩对话';
  String get activityPlanning => '正在规划下一步';

  /// The whimsy phrases it muses, one a line.
  String get activityMusings =>
      '冥思苦想\n琢磨一下\n慢慢酝酿\n深思熟虑\n文火慢炖\n修修补补\n融会贯通\n反复掂量\n'
      '连点成线\n追一个直觉\n酝酿计划\n孵化方案\n权衡利弊\n理清头绪\n赶着一群 token\n'
      '召唤上下文\n请教小黄鸭\n在餐巾纸上打草稿\n眯眼看 diff\n数括号\n和编译器交朋友\n'
      '与类型系统谈判\n驯服边界情况\n追踪调用栈\n翻阅文档\n探索代码库\n摇一摇魔法 8 号球\n'
      '绑定 Monad\n求问神谕\n打磨计划\n打个腹稿\n掐指一算\n抽丝剥茧\n顺藤摸瓜\n'
      '在脑子里跑一遍\n把思路捋直\n拆解问题';
  String activityMusingsCommand(String name) =>
      '对着 $name 的输出点点头\n品一品 $name 的输出\n给 $name 的输出划重点\n'
      '看 $name 跑出了什么名堂\n把 $name 的结果过一遍';
  String activityMusingsCommandFailed(String name) =>
      '和 $name 的报错大眼瞪小眼\n盯着 $name 的报错挠头\n给 $name 的报错号号脉\n'
      '琢磨 $name 为什么不高兴\n顺着 $name 的报错往回找';
  String activityMusingsRead(String name) =>
      '把 $name 翻来覆去地看\n在 $name 里找线头\n跟 $name 混个脸熟\n'
      '在 $name 的字里行间找答案\n把 $name 记在心里';
  String activityMusingsEdit(String name) =>
      '欣赏刚改好的 $name\n替 $name 捏把汗\n回头再瞄一眼 $name\n'
      '想想 $name 还缺点啥\n给 $name 收个尾';
  String activityMusingsSearch(String name) =>
      '在 $name 处结果里淘金\n从 $name 处结果里挑出真身\n顺着 $name 条线索摸过去';
  String activityMusingsFolder(String name) =>
      '在 $name 里东张西望\n给 $name 点个名\n摸清 $name 的家底';
  String activityMusingsWeb(String name) =>
      '从 $name 抄点笔记\n消化 $name 上看来的东西';
  String activityMusingsAgent(String name) =>
      '听 $name 汇报\n批改 $name 交上来的作业\n消化 $name 带回来的情报';
  String activityMusingsMcp(String name) =>
      '拆 $name 寄回来的包裹\n看 $name 回了些什么';
  String get activityMusingsBrowser => '端详页面截图\n看看浏览器里发生了什么';
  String get activityMusingsImage => '端详刚画好的图\n给新图挑挑刺';
  String get activityMusingsDenied => '收到，换条路走\n另想办法';

  // Agent step (a subagent's card).

  String get agentElapsedHint => '已运行时长：续跑的各次累计在内';
  String get agentStateDone => '已完成';
  String get agentStateFailed => '失败';
  String get agentStateRunning => '运行中';
  String get agentStateRunningInBackground => '在后台运行';
  String get statusRunningInBackground => '在后台运行';
  String chatSubagentSemantics(String description, String status) =>
      '子智能体 $description，$status';
  String get chatOpensItsConversation => '打开其对话';
  String get chatBackground => '转到后台';
  String get chatKeepRunningHint => '让它继续运行，智能体接着往下进行';
  String get chatStop => '停止';
  String chatTokens(String tokens) => '$tokens token';
  String chatToolCount(int count) => '$count 个工具';

  // Agent message card.

  String chatAgentMessageSemantics(String agent) => '来自子智能体 $agent 的消息';
  String get chatAgentMessageSent => '发来消息';

  // Command step.

  String get commandCopyCommand => '复制命令';
  String get commandCopyOutput => '复制输出';
  String get commandInBackground => '在后台';
  String get commandMore => '更多';
  String get commandMoveToBackground => '转到后台';
  String get commandStarted => '已启动';

  // Durations and counts.

  String durationSeconds(int seconds) => '$seconds秒';
  String durationMinutesSeconds(int minutes, int seconds) =>
      '$minutes分$seconds秒';
  String durationHoursMinutes(int hours, int minutes) => '$hours小时$minutes分';

  // Goals.

  String get goalAdopt => '设为目标';
  String get goalAdopted => '已设为目标';

  // Notices (a compaction's divider).

  String get noticeCompacted => '对话已压缩';
  String get noticeCompactedAuto => '对话已自动压缩';
  String noticeCompactedFromTo(String before, String after) =>
      '$before → $after token';
  String noticeCompactedTokens(String tokens) => '$tokens token';
  String get noticeCompactedTooLong => '对话已提前压缩：服务商以超出模型上下文为由拒绝了请求';
  String noticeCompactedTooLongWindow(String window) =>
      '对话已提前压缩：服务商以超出模型上下文为由拒绝了请求，模型实际能用的比设定的 $window 小';

  // Plan card.

  String get planApproved => '已批准';
  String get planAwaiting => '待开始';
  String get planCardLabel => '计划';
  String planCardRound(int round) => 'v$round';
  String get planDrafting => '起草中';
  String get planSentBack => '已退回';

  // Sessions (the `session_*` steps and cards).

  String get sessionAnswer => '去回答';
  String get sessionOpen => '打开对话';
  String get sessionShowLess => '收起';
  String get sessionShowMore => '展开';
  String sessionStepDone(String action) => switch (action) {
    'new' => '开了对话',
    'send' => '派活给',
    'wait' => '等了',
    'read' => '看了',
    'stop' => '停下了',
    'changes' => '查看了改动',
    'list' => '列出了对话',
    'models' => '看了可用模型',
    _ => '统筹了',
  };
  String sessionStepRunning(String action) => switch (action) {
    'new' => '正在开对话',
    'send' => '正在派活给',
    'wait' => '正在等',
    'read' => '正在看',
    'stop' => '正在停下',
    'changes' => '正在查看改动',
    'list' => '正在列出对话',
    'models' => '正在看可用模型',
    _ => '正在统筹',
  };

  // Files and images.

  String get fileLinkPreview => '预览';
  String get imageCopy => '复制图片';
  String get shownImage => '图片';
  String get sidePanelOpenDiff => '在侧栏中查看改动';
  String get sidePanelOpenFile => '在侧栏中打开';
  String get openInDefaultApp => '使用默认应用打开';
  String get revealInFileManager => '在访达中显示';

  // Tool calls: what each kind did, or does while running.

  String get toolAgent => '智能体';
  String get toolAsked => '提问';
  String get toolAsking => '正在提问';
  String get toolEdited => '已编辑';
  String get toolEditing => '正在编辑';
  String get toolFetched => '已获取';
  String get toolFetching => '正在获取';
  String get toolGeneratedImage => '已生成图片';
  String get toolGeneratingImage => '正在生成图片';
  String get toolGrepped => '已搜索';
  String get toolGrepping => '正在搜索';
  String get toolImageFailed => '图片未生成';
  String get toolListed => '已列出';
  String get toolListing => '正在列出';
  String get toolProposedGoal => '提议目标';
  String get toolProposingGoal => '正在提议目标';
  String get toolQuestionSkipped => '已跳过提问';
  String get toolRan => '已运行';
  String get toolRead => '已读取';
  String get toolReading => '正在读取';
  String get toolRunning => '正在运行';
  String get toolSearched => '已搜索';
  String get toolSearching => '正在搜索';
  String get toolSending => '正在说';
  String get toolSent => '说';
  String get toolUpdatedTodos => '已更新待办';
  String get toolUpdatingTodos => '正在更新待办';
  String get toolUsed => '已使用';
  String get toolUsing => '正在使用';
  String toolLines(String range) => '第 $range 行';

  // Todo lists.

  String get todoAdded => '添加待办';
  String get todoAllDone => '全部完成';
  String get todoChecked => '查看待办';
  String get todoCompleted => '完成待办';
  String todoCount(int done, int total) => '待办 $done/$total';
  String get todoNone => '列表为空';
  String get todoRemoved => '删除待办';
  String get todoStarted => '开始待办';
  String get todoUpdated => '更新待办';

  // A browser step (the `browser_*` tools), by its action.

  String browserStepDone(String action) => switch (action) {
    'tabs' => '已列出标签页',
    'open' => '已打开',
    'navigate' => '已前往',
    'back' => '已后退',
    'forward' => '已前进',
    'reload' => '已重新加载',
    'snapshot' => '已读取页面',
    'screenshot' => '已截图',
    'click' => '已点击',
    'type' => '已输入',
    'press' => '已按下',
    'scroll' => '已滚动',
    'evaluate' => '已运行',
    'close' => '已关闭标签页',
    'console' => '已查看控制台',
    'network' => '已查看请求',
    'request' => '已查看请求',
    'performance' => '已分析性能',
    'recordStart' => '已开始录制性能',
    'recordStop' => '已分析性能',
    'emulate' => '已模拟',
    'watch' => '已看完你的操作',
    'act' => '已执行',
    'inspect' => '已检查元素',
    'sources' => '已查看源码',
    'breakpoints' => '已设置断点',
    'debugger' => '已调试',
    'intercept' => '已拦截请求',
    'storage' => '已查看站点数据',
    'dialog' => '已应答弹窗',
    'coverage' => '已统计覆盖率',
    'memory' => '已分析内存',
    'history' => '已查看调试记录',
    _ => '已使用浏览器',
  };
  String browserStepRunning(String action) => switch (action) {
    'tabs' => '正在列出标签页',
    'open' => '正在打开',
    'navigate' => '正在前往',
    'back' => '正在后退',
    'forward' => '正在前进',
    'reload' => '正在重新加载',
    'snapshot' => '正在读取页面',
    'screenshot' => '正在截图',
    'click' => '正在点击',
    'type' => '正在输入',
    'press' => '正在按下',
    'scroll' => '正在滚动',
    'evaluate' => '正在运行',
    'close' => '正在关闭标签页',
    'console' => '正在查看控制台',
    'network' => '正在查看请求',
    'request' => '正在查看请求',
    'performance' => '正在分析性能',
    'recordStart' => '正在开始录制性能',
    'recordStop' => '正在分析性能',
    'emulate' => '正在模拟',
    'watch' => '正在看你操作',
    'act' => '正在执行',
    'inspect' => '正在检查元素',
    'sources' => '正在查看源码',
    'breakpoints' => '正在设置断点',
    'debugger' => '正在调试',
    'intercept' => '正在拦截请求',
    'storage' => '正在查看站点数据',
    'dialog' => '正在应答弹窗',
    'coverage' => '正在统计覆盖率',
    'memory' => '正在分析内存',
    'history' => '正在查看调试记录',
    _ => '正在使用浏览器',
  };

  // A thought's header.

  String get stepBriefly => '片刻';
  String get stepThinking => '正在思考';
  String get stepThought => '已思考';

  // Common.

  String get commonCopy => '复制';
  String get commonClose => '关闭';
  String get commonDismiss => '关闭';
  String get turnCopied => '已复制';
}

/// As the desktop's `AppLocalizations`, reduced to the phone's (Chinese).
typedef AppLocalizations = L10n;

/// The strings everywhere, as the desktop's `englishLocalizations` is its
/// fallback: the phone has one language.
const AppLocalizations englishLocalizations = L10n();

extension AppLocalizationsContext on BuildContext {
  /// The strings of the locale in scope; the phone's one language.
  AppLocalizations get l10n => englishLocalizations;
}
