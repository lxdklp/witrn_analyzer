<p align="center">
  <img src="assets/branding/witrn_analyzer_windows.png" alt="WITRN Analyzer" width="128" />
</p>
<p align="center"> <img src=https://img.shields.io/badge/Windows%20%7C%20macOS%20%7C%20Linux%20%7C%20Android-1?style=for-the-badge&label=Platform> <img src=https://img.shields.io/badge/GPLv3-1?style=for-the-badge&label=License> </p>
<p align="center"> <img src=https://img.shields.io/badge/3.47.7-1?logo=flutter&logoColor=white&style=for-the-badge&label=Flutter> <img src=https://img.shields.io/badge/Dart-1?logo=dart&logoColor=white&style=for-the-badge&label=language> </p>
<p align="center"><img src=https://img.shields.io/github/v/release/lxdklp/witrn_analyzer?style=for-the-badge> <img  src=https://img.shields.io/github/stars/lxdklp/witrn_analyzer?style=for-the-badge></p>

# WITRN Analyzer

一个使用 Flutter 编写、采用 Material Design 3 风格的跨平台 WITRN K2 USB 功率计上位机 ，支持 Windows、macOS、Linux 和 Android。

搭配维简 WITRN K2 使用，通过 USB HID 采集 PD 报文与电参数据，查看充电协商过程、供电能力和功率变化。

## 功能

- **PD 报文分析**：查看报文列表、原始字节和字段详情，解析 PDO / RDO、PPS、EPR、VDM 及扩展消息，支持扩展消息分片重组。
- **报文筛选**：搜索消息、序号和原始字节，按 SOP 类型筛选，显示或隐藏 GoodCRC。
- **电参与曲线**：显示电压、电流、功率、温度及 CC1 / CC2、D+ / D− 数据；绘制电压、电流、功率和温度曲线，支持缩放、平移和报文事件标线。
- **源能力查看**：展示设备协商中收到的供电能力及请求信息。
- **CSV 导入导出**：分别保存和载入 PD 报文与图表数据，便于离线分析。
- **设备与解析设置**：自定义 USB VID / PID、HID 报告布局、1–10 Hz HID 读取频率，切换 WITRN 兼容或标准 USB PD 解析模式。
- **外观与交互**：适配桌面和手机布局，支持浅色 / 深色模式、自定义主题色、Android 动态配色和 macOS 原生菜单栏。

## 安装

发布版本可从本仓库的 [GitHub Releases](../../releases) 下载。手动触发构建后，也可在 [GitHub Actions](../../actions) 对应运行记录的 Artifacts 中下载产物。

| 平台 | 架构 | 安装包 |
| --- | --- | --- |
| Windows | x64 / ARM64 | EXE 安装程序、ZIP |
| macOS | Universal（Intel / Apple Silicon）及 ARM64 | DMG |
| Linux | x64 / ARM64 | DEB、AppImage、ZIP |
| Android | armeabi-v7a / arm64-v8a / x86_64 | 分架构 APK、通用 APK |
