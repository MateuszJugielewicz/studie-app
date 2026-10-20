# EasySesh for Android

The Android app is a 1:1 port of the iOS app (`ios/`): same screens, flows, look, Supabase backend,
translations (`ios/EasySesh/Localizable.xcstrings`) and legal texts (`legal/`).
Kotlin + Jetpack Compose, minimum Android 8.0 (API 26).

## Run it on Windows

1. Install **Android Studio** (https://developer.android.com/studio) – the default options are fine.
2. Open Android Studio → **Open** → pick the `android` folder of this repository.
   Wait until "Gradle sync" finishes (the first time takes a few minutes).
3. Phone: Settings → About phone → tap **Build number** 7 times → back → Developer options →
   turn on **USB debugging**. Connect it with a cable and allow the computer.
   (Or use an emulator: Device Manager → Create device → Pixel 8 → API 35.)
4. Press the green **Run ▶** button.

Without Android Studio, from PowerShell in the `android` folder:

```powershell
.\gradlew.bat assembleDebug
# The app is then at app\build\outputs\apk\debug\app-debug.apk
```

## Keys

The public keys (Supabase URL + publishable key, Stripe publishable key, support email) are read
from `ios/Config/App.xcconfig`, so both apps always use the same backend. Everything else goes in
`android/local.properties` (not committed). Create the file if it doesn't exist:

```properties
# Optional – override the shared iOS values
#supabaseUrl=https://gdebbieifsvspszmevwa.supabase.co
#supabaseAnonKey=sb_publishable_...
#stripePublishableKey=pk_live_...
#supportEmail=support@yourdomain.com

# Google sign-in in the app (Web client ID from Google Cloud → APIs & Services → Credentials).
# Without it, Google sign-in opens in the browser instead.
googleWebClientId=1234567890-abc.apps.googleusercontent.com

# Push notifications (Firebase console → Project settings → General → Your apps → Android app)
firebaseProjectId=easysesh-12345
firebaseAppId=1:1234567890:android:abcdef
firebaseApiKey=AIza...
firebaseSenderId=1234567890

# Release signing (see "Play Store" below)
releaseStoreFile=C:/Users/you/easysesh-release.jks
releaseStorePassword=...
releaseKeyAlias=easysesh
releaseKeyPassword=...
```

Never put the Stripe **secret** key or the Supabase **service_role** key in the app.

## Backend setup for Android

- **Sign-in links** (email confirmation, password reset, Apple/Google in the browser) come back on
  `easysesh://auth-callback` – the same as iOS, nothing to add in Supabase.
- **Google sign-in**: in Google Cloud create an OAuth client of type *Android* (package
  `com.easysesh.app` + the SHA-1 of your signing key: `.\gradlew.bat signingReport`) and one of type
  *Web*. Put the Web client ID in `googleWebClientId` and in Supabase → Authentication → Providers →
  Google (Client IDs).
- **Push notifications**: create a Firebase project, add an Android app with package
  `com.easysesh.app`, copy its values into `local.properties` (above). Then Firebase → Project
  settings → Service accounts → **Generate new private key**, and set three Supabase secrets from
  that JSON file:

  ```powershell
  .\supabase.exe secrets set --project-ref gdebbieifsvspszmevwa FCM_PROJECT_ID=easysesh-12345 FCM_CLIENT_EMAIL=firebase-adminsdk-xxx@easysesh-12345.iam.gserviceaccount.com
  .\supabase.exe secrets set --project-ref gdebbieifsvspszmevwa FCM_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\nMIIE...\n-----END PRIVATE KEY-----\n"
  .\supabase.exe functions deploy send-push --project-ref gdebbieifsvspszmevwa --no-verify-jwt
  ```

## Play Store

1. Create the upload key once (keep the file and passwords safe – every update needs them):

   ```powershell
   keytool -genkeypair -v -keystore C:\Users\you\easysesh-release.jks -alias easysesh -keyalg RSA -keysize 2048 -validity 10000
   ```

   (`keytool` comes with Android Studio: `"C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe"`.)
2. Add the `release…` lines to `local.properties`, raise `versionCode` in `app/build.gradle.kts`
   for every upload, then build the bundle:

   ```powershell
   .\gradlew.bat bundleRelease
   # Upload app\build\outputs\bundle\release\app-release.aab in Play Console
   ```

3. Play Console: everything Google checks (Data safety, target audience, content rating, closed
   testing, account deletion link, …) is listed in `docs/PLAY_STORE_RELEASE.md`. Payment keys and
   Google Pay: `docs/PAYMENTS.md`.

## Screenshots without a phone

`app/src/test/.../ScreenshotTest.kt` renders screens on the computer:

```powershell
.\gradlew.bat :app:testDebugUnitTest --tests "*ScreenshotTest*" -Proborazzi.test.record=true
# Images: app\build\screenshots\
```
