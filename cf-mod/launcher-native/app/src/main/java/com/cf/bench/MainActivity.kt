package com.cf.bench

import android.app.DownloadManager
import android.content.*
import android.database.Cursor
import android.net.Uri
import android.os.*
import android.provider.Settings
import android.view.View
import android.view.ViewGroup
import android.widget.*
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.FileProvider
import java.io.File

class MainActivity : AppCompatActivity() {

    private val modUrl =
        "https://github.com/Scratchhhh/counterflame-releases/releases/download/v1.4.1-c7/CounterFlame-1.4.1-c7.apk"
    private var downloadId = -1L
    private lateinit var dm: DownloadManager
    private lateinit var progress: ProgressBar
    private lateinit var status: TextView
    private val handler = Handler(Looper.getMainLooper())
    private val poller = object : Runnable {
        override fun run() { pollDownload(); handler.postDelayed(this, 500) }
    }

    private val rowData = listOf(
        "ESP"                       to "box · name · hp · tracer",
        "Aim"                       to "fov · smooth · head/neck/chest",
        "Fly / Noclip"              to "фиксированная скорость · коллайдер off",
        "Skin changer"              to "8 локальных пресетов, без неона",
        "Kill all"                  to "arm → fire · ApplyDamage всем врагам",
        "Misc"                      to "god · rapid · no spread · speed · wallbang",
    )

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        dm = getSystemService(DOWNLOAD_SERVICE) as DownloadManager
        progress = findViewById(R.id.progress)
        status = findViewById(R.id.status)

        findViewById<Button>(R.id.btnFetch).setOnClickListener { fetch() }
        findViewById<Button>(R.id.btnSite).setOnClickListener {
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://counterflame.com")))
        }

        val root = findViewById<ViewGroup>(android.R.id.content)
        val labels = root.findAllViewsWithId(R.id.rowTitle)
        val hints  = root.findAllViewsWithId(R.id.rowHint)
        for ((i, pair) in rowData.withIndex()) {
            if (i < labels.size) (labels[i] as TextView).text = pair.first
            if (i < hints.size)  (hints[i]  as TextView).text = pair.second
        }

        registerReceiver(
            onComplete,
            IntentFilter(DownloadManager.ACTION_DOWNLOAD_COMPLETE),
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU)
                Context.RECEIVER_EXPORTED
            else 0
        )
    }

    private fun fetch() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
            val i = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:$packageName"))
            startActivity(i)
            Toast.makeText(this, "Разреши установку из этого источника и жми fetch снова", Toast.LENGTH_LONG).show()
            return
        }
        val file = File(getExternalFilesDir(null), "CounterFlame-1.4.1-c7-mod.apk")
        if (file.exists()) file.delete()
        val req = DownloadManager.Request(Uri.parse(modUrl))
            .setTitle("CounterFlame mod APK")
            .setDescription("1.4.1-c7")
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
            .setDestinationUri(Uri.fromFile(file))
            .setAllowedOverMetered(true)
            .setAllowedOverRoaming(true)
        downloadId = dm.enqueue(req)
        status.text = "скачивание…"
        progress.progress = 0
        handler.post(poller)
    }

    private fun pollDownload() {
        if (downloadId < 0) return
        val q = DownloadManager.Query().setFilterById(downloadId)
        val c: Cursor = dm.query(q) ?: return
        c.use {
            if (!it.moveToFirst()) return
            val bytes = it.getLong(it.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR))
            val total = it.getLong(it.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES))
            val st = it.getInt(it.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
            if (total > 0) progress.progress = (bytes * 100 / total).toInt()
            status.text = "скачивание… ${bytes / 1_048_576} / ${total / 1_048_576} МБ"
            if (st == DownloadManager.STATUS_FAILED) {
                status.text = "ошибка загрузки"
                handler.removeCallbacks(poller)
            }
        }
    }

    private val onComplete = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context?, intent: Intent?) {
            val id = intent?.getLongExtra(DownloadManager.EXTRA_DOWNLOAD_ID, -1) ?: -1
            if (id != downloadId) return
            handler.removeCallbacks(poller)
            val uri = dm.getUriForDownloadedFile(id) ?: return
            status.text = "готов — открываю установщик"
            progress.progress = 100
            val install = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(install)
        }
    }

    override fun onDestroy() {
        unregisterReceiver(onComplete)
        handler.removeCallbacks(poller)
        super.onDestroy()
    }
}

private fun ViewGroup.findAllViewsWithId(id: Int): List<View> {
    val out = mutableListOf<View>()
    walk(this, id, out)
    return out
}
private fun walk(v: View, id: Int, out: MutableList<View>) {
    if (v.id == id) out.add(v)
    if (v is ViewGroup) for (i in 0 until v.childCount) walk(v.getChildAt(i), id, out)
}
