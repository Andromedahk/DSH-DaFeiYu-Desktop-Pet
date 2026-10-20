# 默认素材与来源

图片基础和原版音效来自 [VKmich16/V](https://github.com/VKmich16/V) 的 `DSH余额桌宠.zip`。Windows 原版图片与音效完整保留在仓库的 `原版（Windows版）/DSH余额桌宠/`。

1.5.0 起蓝色大肥鱼改用三张 1024 × 1024 表情立绘（`expression_happy/angry/nervous.png`）：平时、失去焦点、扣费中各一张，均由用户提供、直接复制为透明 PNG。旧的 1536 × 1024 单张立绘 `sprite.png` 仍保留在此目录，仅作历史素材，应用已不再加载它。

1.3.0 新增三张同项目其他对话中已生成的角色图，均为 1536×1024 RGBA 原文件复制：GPT龙娘和大小姐Claude取自“创建并优化DSH大肥鱼桌宠”的第一组成品；北美猫娘Gemini取自“按人设修改大肥鱼图片”的 `character.png` 透明背景清理版。没有重新生成或改动图片内容。

| 文件 | 用途 | SHA-256 |
| --- | --- | --- |
| `expression_happy.png` | 1024 × 1024 RGBA，平时表情（开心） | `53e3d2c41bca1ca87cf8d9ba345d13260724c3f54263f59bce850343ab7c2d37` |
| `expression_angry.png` | 1024 × 1024 RGBA，失去焦点表情（生气） | `7b0c82e6934018d628bea353eb81b7f75c70cbcdafa7d3437f2fdf90be11339e` |
| `expression_nervous.png` | 1024 × 1024 RGBA，扣费表情（紧张） | `595bc52671432c69b6f7793772cb3dba27b1add754ac7750748c04cc8e41929f` |
| `sprite.png` | 1536 × 1024 RGBA，旧版单张立绘（已不再加载，仅存档） | `a98329d36dd9169a1856f3a396bc9e602ed1a739bd3097eead1b744c6bb3dd71` |
| `sprite-gpt.png` | GPT龙娘：白发、龙角、龙尾 | `41f79346666fbb776ee2baef2a0cf044850a50e30c177b3adf9bb14e84296467` |
| `sprite-claude.png` | 大小姐Claude：橙发、花饰、无尾巴 | `81f0e787057dd9d5e400e5f43a44a1b55da4adfa7329aa712d986531cbd5d90d` |
| `sprite-gemini.png` | 北美猫娘Gemini：蓝紫发、异色瞳、毛绒尾巴 | `ad5fbeb07c2212476d4670ec56b8e7202e21f05b42ab0461cf3150a43f91a2ef` |
| `sprite-deepseek-offline.png` | 用户提供的 1536 × 1024 RGBA 抱盆图；仅用于蓝色大肥鱼未连接状态，原文件直接复制 | `fb4c5cb3001ca43d268d2e3bdf39b9d984e28d592e3b73e46e6fd44ccebb4555` |
| `hit.mp3` | 原版扣费打击音效 | `43fa877b537d8cbfbd676d76109b9a960551bfeae06c62e2d1a7d64d3994cb29` |

补全图片来源、参考与提示词见 [`artwork/left-completion-v1`](../artwork/left-completion-v1/README.md)。Windows 原始 1024 × 1024 图片 SHA-256 为 `5bc1d8f1f347c430dd662ad8ff3da8d0dff3df9f290712efe36d004b7b103e69`。

余额文字、状态点及动画由 macOS 应用实时绘制。`PetCharacter.swift` 为每个角色保存文字安全区，`PetLayout.swift` 将其映射到视图；图片绘制和透明命中使用同一缩放矩形。以下坐标以各原图左上角为原点：

| 角色 | 左上 TL | 右上 TR | 左下 BL | 右下 BR |
| --- | --- | --- | --- | --- |
| 蓝色大肥鱼 / GPT龙娘 / 大小姐Claude | (1060,699) | (1413,644) | (1090,889) | (1443,834) |
| 北美猫娘Gemini | (1065,699) | (1400,646) | (1095,889) | (1430,836) |

Gemini 的右手伸入屏幕较多，因此文字区域单独收窄以避开手指。

上游原作者说明 UI 图片由其处理；上游暂未附许可证。这里保留来源说明，不另行授予上游代码、素材或衍生图片的许可。
