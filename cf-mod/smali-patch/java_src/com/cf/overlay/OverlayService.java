package com.cf.overlay;

import android.app.*;
import android.content.*;
import android.graphics.PixelFormat;
import android.os.*;
import android.view.*;

public class OverlayService extends Service {
    private WindowManager wm;
    private View v;

    @Override public IBinder onBind(Intent i){ return null; }

    @Override public int onStartCommand(Intent intent, int flags, int sid) {
        if (v != null) return START_STICKY;
        wm = (WindowManager) getSystemService(WINDOW_SERVICE);
        WindowManager.LayoutParams lp = new WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            Build.VERSION.SDK_INT >= 26
                ? WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                : WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                | WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN
                | WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT);
        v = new View(this) {
            @Override public boolean onTouchEvent(MotionEvent e) {
                int a;
                switch (e.getActionMasked()) {
                    case MotionEvent.ACTION_DOWN: a = 0; break;
                    case MotionEvent.ACTION_MOVE: a = 1; break;
                    default: a = 2;
                }
                Bridge.feedTouch(e.getX(), e.getY(), a);
                return true;
            }
        };
        wm.addView(v, lp);
        return START_STICKY;
    }

    @Override public void onDestroy() {
        if (v != null && wm != null) wm.removeView(v);
        super.onDestroy();
    }
}
