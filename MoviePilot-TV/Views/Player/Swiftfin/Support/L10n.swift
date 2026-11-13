//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//
// 本文件改自 Swiftfin：Shared/Strings/Strings.swift、Translations/zh-Hans.lproj/Localizable.strings
// Modifications for MoviePilot-TV are also licensed under MPL-2.0.
//
// 修改：Swiftfin 的 SwiftGen 生成文件只保留播放器用到的键，取值直接写入 Swiftfin 的简体中文翻译（缺译时用英文原文）。
//

import Foundation

// swiftlint:disable all
nonisolated enum L10n {

    static let aspectFill = "保持纵横比填充"
    static let audio = "音频"
    static let audioBitrate = "音频码率"
    static let audioCodec = "音频编码"
    static let audioOffset = "音频偏移"
    static let audioSampleRate = "音频采样率"
    static let auto = "自动"
    static let autoPlay = "自动播放"
    static let bitrate = "比特率"
    static let bitsPerSecond = "bps"
    static let cancel = "取消"
    static let captionStyleSettings = "开放字幕样式设置"
    static let channels = "声道"
    static let chapters = "章节"
    static let close = "关闭"
    static let closePlayer = "关闭播放器"
    static let closePlayerWarning = "您确定要关闭播放器吗？"
    static let container = "格式"
    static let custom = "自定义设置"
    static let decrease = "递减"
    static let direct = "直接串流播放"
    static let directPlay = "直接播放"
    static let disabled = "禁用"
    static let dismiss = "忽略"
    static func endsAt(_ p1: Any) -> String {
        String(format: "结束于 %@", String(describing: p1))
    }
    static func episodeNumber(_ p1: Any) -> String {
        String(format: "第%1$@集", String(describing: p1))
    }
    static let error = "错误"
    static let fromBeginning = "从头播放"
    static let gigabitsPerSecond = "Gbps"
    static let hardwareAcceleration = "硬件加速"
    static let increase = "递增"
    static let info = "简介"
    static let kilobitsPerSecond = "kpbs"
    static let landscape = "剧照"
    static let live = "现场直播"
    static let maximum = "最大限度"
    static let mediaPlayback = "媒体播放"
    static let megabitsPerSecond = "Mbps"
    static let menu = "菜单"
    static let method = "方法"
    static let nextChapter = "下一章节"
    static let `none` = "无"
    static let off = "关"
    static let ok = "确定"
    static let on = "开"
    static let originalMediaInfo = "媒体源信息"
    static let people = "演员"
    static let pictureInPicture = "画中画"
    static let playNextItem = "下一集"
    static let playPreviousItem = "上一集"
    static let playback = "播放"
    static let playbackQuality = "播放质量"
    static let playbackSpeed = "播放速度"
    static let portrait = "海报"
    static func posterAccessibilityStartTime(_ p1: Any) -> String {
        String(format: "开始时间：%1$@", String(describing: p1))
    }
    static let previousChapter = "上一章节"
    static let primarySubtitles = "首选字幕"
    static let `protocol` = "协议"
    static let queue = "选集"
    static let reset = "重置"
    static let resolution = "分辨率"
    static let retry = "重试"
    static func seasonAndEpisode(_ p1: Any, _ p2: Any) -> String {
        String(format: "第%1$@季:%2$@集", String(describing: p1), String(describing: p2))
    }
    static let secondarySubtitleOffset = "辅助字幕偏移"
    static let secondarySubtitles = "辅助字幕"
    static let session = "详情"
    static let showOnSkipBack = "向后跳转时显示"
    static let size = "大小"
    static let skip = "跳转"
    static let source = "来源"
    static let square = "盘面"
    static let streamInfo = "串流信息"
    static func streamInfoWithMethod(_ p1: Any) -> String {
        String(format: "%@ 信息", String(describing: p1))
    }
    static let subtitleOffset = "字幕偏移"
    static let subtitleTrack = "轨道"
    static let subtitles = "字幕"
    static let system = "跟随系统"
    static let terabitsPerSecond = "Tbps"
    static let textStyle = "文本样式"
    static let transcodeProgress = "转码进度"
    static let transcodeReasons = "转码原因"
    static let trickplays = "进度条预览图"
    static let unableToOpenSettings = "无法打开设置"
    static let unableToSeek = "无法跳转。请重试。"
    static let unknown = "未知"
    static let unknownError = "未知错误"
    static let version = "版本"
    static let video = "视频"
    static let videoBitRate = "视频码率"
    static let videoCodec = "视频编码"
    static let videoPlayer = "视频播放器"
    static let videoRangeType = "动态范围类型"
    static let videoResolution = "分辨率"
}
