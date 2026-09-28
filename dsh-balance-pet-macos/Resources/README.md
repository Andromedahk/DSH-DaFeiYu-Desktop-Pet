# 默认素材与来源

图片基础和原版音效来自 [VKmich16/V](https://github.com/VKmich16/V) 的 `DSH余额桌宠.zip`。Windows 原版图片与音效完整保留在仓库的 `原版（Windows版）/DSH余额桌宠/`。

1.2.0 将默认图片替换为已生成的左侧头发与鲸尾补全版本；直接复制透明 PNG，没有拉伸、裁切或再次生成。补全图含轻微生成重绘，不能视作原图逐像素不变的扩边。

| 文件 | 用途 | SHA-256 |
| --- | --- | --- |
| `sprite.png` | 1536 × 1024 RGBA，补全头发与鲸尾的大肥鱼及手持平板 | `a98329d36dd9169a1856f3a396bc9e602ed1a739bd3097eead1b744c6bb3dd71` |
| `hit.mp3` | 原版扣费打击音效 | `43fa877b537d8cbfbd676d76109b9a960551bfeae06c62e2d1a7d64d3994cb29` |

补全图片来源、参考与提示词见 [`artwork/left-completion-v1`](../artwork/left-completion-v1/README.md)。Windows 原始 1024 × 1024 图片 SHA-256 为 `5bc1d8f1f347c430dd662ad8ff3da8d0dff3df9f290712efe36d004b7b103e69`。

余额文字、状态点及动画由 macOS 应用实时绘制。`PetLayout.swift` 的文字安全区按新图上边原点坐标 TL(1060,699)、TR(1413,644)、BL(1090,889)、BR(1443,834) 校准，避开边框与手指；图片绘制和透明命中使用同一缩放矩形。

上游原作者说明 UI 图片由其处理；上游暂未附许可证。这里保留来源说明，不另行授予上游代码、素材或衍生图片的许可。
