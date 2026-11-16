# اپ‌بلاکر: سرویس دسترسی‌پذیری + صفحه‌ی مسدودسازی + پل Flutter (از patch_android.py صدا زده می‌شود؛ متغیر root در دسترس است)
PKG = 'com.jojo.study_companion'
main = root / 'android/app/src/main'
kdir = main / 'kotlin' / PKG.replace('.', '/')
kdir.mkdir(parents=True, exist_ok=True)
(main / 'res/xml').mkdir(parents=True, exist_ok=True)
(main / 'res/values').mkdir(parents=True, exist_ok=True)

(main / 'res/xml/blocker_service.xml').write_text('''<?xml version="1.0" encoding="utf-8"?>
<accessibility-service xmlns:android="http://schemas.android.com/apk/res/android"
    android:accessibilityEventTypes="typeWindowStateChanged"
    android:accessibilityFeedbackType="feedbackGeneric"
    android:canRetrieveWindowContent="false"
    android:notificationTimeout="100"
    android:description="@string/blocker_desc"/>
''', encoding='utf8')
(main / 'res/values/blocker_strings.xml').write_text('''<?xml version="1.0" encoding="utf-8"?>
<resources><string name="blocker_desc">فقط تشخیص می‌دهد کدام برنامه باز شده تا برنامه‌های انتخاب‌شده‌ی تو را هنگام تمرکز ببندد. هیچ داده‌ای جمع‌آوری یا ارسال نمی‌شود.</string></resources>
''', encoding='utf8')

(kdir / 'Blocker.kt').write_text(f'''package {PKG}

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.accessibility.AccessibilityEvent
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import android.app.Activity

object Blocker {{
    fun p(c: Context) = c.getSharedPreferences("blocker", 0)
    fun shouldBlock(c: Context, pkg: String): Boolean {{
        val p = p(c)
        if (!p.getBoolean("on", false)) return false
        if (!p.getBoolean("always", false) && System.currentTimeMillis() > p.getLong("focusUntil", 0)) return false
        return p.getStringSet("apps", emptySet())!!.contains(pkg)
    }}
}}

class BlockerService : AccessibilityService() {{
    private var last = 0L
    override fun onAccessibilityEvent(e: AccessibilityEvent?) {{
        if (e?.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val pkg = e.packageName?.toString() ?: return
        if (pkg == packageName || !Blocker.shouldBlock(this, pkg)) return
        val now = System.currentTimeMillis()
        if (now - last < 800) return
        last = now
        performGlobalAction(GLOBAL_ACTION_HOME)
        startActivity(Intent(this, BlockActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }}
    override fun onInterrupt() {{}}
}}

class BlockActivity : Activity() {{
    override fun onCreate(b: Bundle?) {{
        super.onCreate(b)
        val d = resources.displayMetrics.density
        val col = LinearLayout(this).apply {{
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.parseColor("#161316"))
            setPadding((32 * d).toInt(), 0, (32 * d).toInt(), 0)
            layoutDirection = View.LAYOUT_DIRECTION_RTL
        }}
        col.addView(TextView(this).apply {{
            text = "الان وقت تمرکزه 🎯"; textSize = 26f; setTextColor(Color.WHITE)
            setTypeface(null, Typeface.BOLD); gravity = Gravity.CENTER
        }})
        col.addView(TextView(this).apply {{
            text = "این برنامه تا پایان جلسه‌ی تمرکز بسته است."; textSize = 15f
            setTextColor(Color.parseColor("#BABABA")); gravity = Gravity.CENTER
            setPadding(0, (12 * d).toInt(), 0, (28 * d).toInt())
        }})
        col.addView(Button(this).apply {{
            text = "برگرد به درس"
            setOnClickListener {{
                packageManager.getLaunchIntentForPackage(packageName)?.let {{ startActivity(it) }}
                finish()
            }}
        }})
        setContentView(col)
    }}
    override fun onBackPressed() {{
        startActivity(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        finish()
    }}
}}
''', encoding='utf8')

(kdir / 'MainActivity.kt').write_text(f'''package {PKG}

import android.content.ComponentName
import android.content.Intent
import android.provider.Settings
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {{
    override fun configureFlutterEngine(engine: FlutterEngine) {{
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, "omid/blocker").setMethodCallHandler {{ call, res ->
            val p = Blocker.p(this)
            when (call.method) {{
                "apps" -> {{
                    val pm = packageManager
                    val q = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
                    val l = pm.queryIntentActivities(q, 0)
                        .filter {{ it.activityInfo.packageName != packageName }}
                        .map {{ mapOf("pkg" to it.activityInfo.packageName, "label" to it.loadLabel(pm).toString()) }}
                        .distinctBy {{ it["pkg"] }}
                        .sortedBy {{ it["label"]!!.lowercase() }}
                    res.success(l)
                }}
                "get" -> res.success(mapOf(
                    "apps" to p.getStringSet("apps", emptySet())!!.toList(),
                    "on" to p.getBoolean("on", false),
                    "always" to p.getBoolean("always", false)))
                "save" -> {{
                    p.edit()
                        .putStringSet("apps", (call.argument<List<String>>("apps") ?: emptyList()).toSet())
                        .putBoolean("on", call.argument<Boolean>("on") ?: false)
                        .putBoolean("always", call.argument<Boolean>("always") ?: false)
                        .apply()
                    res.success(null)
                }}
                "focus" -> {{
                    val s = (call.arguments as? Int) ?: 0
                    p.edit().putLong("focusUntil", if (s <= 0) 0L else System.currentTimeMillis() + s * 1000L).apply()
                    res.success(null)
                }}
                "enabled" -> {{
                    val cn = ComponentName(this, BlockerService::class.java).flattenToString()
                    val s = Settings.Secure.getString(contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: ""
                    res.success(s.split(':').any {{ it.equals(cn, true) }})
                }}
                "openSettings" -> {{
                    startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    res.success(null)
                }}
                else -> res.notImplemented()
            }}
        }}
    }}
}}
''', encoding='utf8')

m = man.read_text(encoding='utf8')
if 'BlockerService' not in m:
    m = m.replace('<application', '''<queries><intent><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/></intent></queries>
    <application''', 1)
    m = m.replace('</application>', '''        <service android:name=".BlockerService" android:exported="true"
            android:permission="android.permission.BIND_ACCESSIBILITY_SERVICE">
            <intent-filter><action android:name="android.accessibilityservice.AccessibilityService"/></intent-filter>
            <meta-data android:name="android.accessibilityservice" android:resource="@xml/blocker_service"/>
        </service>
        <activity android:name=".BlockActivity" android:exported="false" android:launchMode="singleTask"
            android:taskAffinity="" android:excludeFromRecents="true"
            android:theme="@android:style/Theme.DeviceDefault.NoActionBar"/>
    </application>''', 1)
    man.write_text(m, encoding='utf8')
print('blocker patched')
