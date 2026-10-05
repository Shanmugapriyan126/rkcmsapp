# RK-CMS Android – build the APK (no Android Studio needed)

## Option A – GitHub (easiest, free)
1. Create a new **private** repository on github.com and upload everything in this folder (keep the `.github` folder).
2. Open the **Actions** tab → **Build RK-CMS APK** → **Run workflow**.
3. After ~5 minutes open the finished run → **Artifacts** → download **RK-CMS-apk** → unzip → `app-debug.apk`.
4. Copy the APK to the phone and install it (allow “Install unknown apps” for your file manager/browser).

## Option B – your own PC
Install Node 20, JDK 17 and Android Studio (for the SDK), then:
    npm install
    npx cap add android
    npx cap sync android
    cd android && ./gradlew assembleDebug      (Windows: gradlew.bat assembleDebug)
APK: android/app/build/outputs/apk/debug/app-debug.apk

## Notes
- Web files live in `www/`. After editing them run `npx cap sync android` and rebuild.
- Supabase URL/key are in `www/supabase-config.js`; run `supabase-setup.sql` in Supabase first.
- This is a debug-signed APK, fine for in-factory sideloading. For Play Store, build a signed release in Android Studio.
