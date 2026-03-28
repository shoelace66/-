package com.example.flutter_chat_demo

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // 启动前台服务，确保应用在后台也能运行
        ChatForegroundService.startService(this)
    }

    override fun onDestroy() {
        super.onDestroy()
        // 应用完全关闭时才停止服务
        if (isFinishing) {
            ChatForegroundService.stopService(this)
        }
    }
}
