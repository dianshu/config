## Skill 步骤不可绕过

当 skill 文档中出现 **MANDATORY / MUST / 必须 / 不允许跳过** 等强制措辞，或明确说"step X 必须在 step Y 之前/之后执行"时：

1. **必须执行**，不允许用以下任何理由跳过：
   - "diff 太小，不值得"
   - "token / 时间成本太高"
   - "我已经看过了，结论一样"
   - "外部 reviewer 也找不出新东西"
   - "judged not worth"
   - 任何其他主观裁量

2. 如果真的觉得某步在当前场景没意义，**停下来问用户**（用 AskUserQuestion 或直接文字提问），不要默默跳过。

3. **不允许"沉默式跳过"**：哪怕最终决定不跑某步，也要在输出里显式说出 "skipping step X because Y, asking user to confirm"，让用户能立刻打断。

判断标准：skill 的硬性步骤是给我执行的，不是给我裁量的。把它当成黑盒指令——除非和 deny 列表里的命令或安全风险冲突，否则一律照做。
