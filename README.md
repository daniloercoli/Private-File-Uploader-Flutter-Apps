# Private File Uploader (Flutter + WordPress)

A privacy-focused mobile client for uploading files directly to **your own WordPress server** via REST API.
Authentication relies on **WordPress Application Passwords** — no external cloud services involved.

> **Server requirement:** install the dedicated WordPress plugin exposing the `/wp-json/private-file-uploader/v1/...` endpoints (upload, listing, etc.).
> After installation, set your **Site URL / Username / Application Password** in **Settings**.

---

## Status & Features

### ✅ Current features

**Home**

* Pick a file using the native file picker and upload it via authenticated **multipart POST**.
* On success:

  * The remote file URL is **copied to clipboard**.
  * The URL is **saved locally** in upload history.
  * The user is prompted:
    *“File URL copied to clipboard. Do you want to send it by email?”*
    → Opens the default mail app with the URL prefilled in the email body.

**Uploads**

* Displays the **server-side file list** (`GET /files`).
* Shows **image thumbnails** for `image/*` MIME types, or a **placeholder** (e.g., PDF icon) otherwise.
* **Tap** or **long-press** → copies the remote URL to clipboard with a short toast.
* Supports **pull-to-refresh**.

**Settings**

* Fields: **Site URL**, **Username**, **Application Password**.
* Persistent storage:

  * URL and Username in shared preferences.
  * Password securely stored in **KeyStore** (Android).
* “Reset” button clears all credentials.

**Info**

* Shows app name and version (read from the OS).
* Built-in **Licenses/About** screen.
* **Copy diagnostics** button: copies non-sensitive device and app info to clipboard (no password).

---

## Requirements

* **Flutter SDK** and Android/iOS toolchain installed.

---

## Quick Setup

1. **Install dependencies**

   ```bash
   flutter pub get
   ```

2. **Android configuration**

   * `android/app/build.gradle` → `minSdkVersion 23`
   * `android/app/src/main/AndroidManifest.xml` →

     ```xml
     <uses-permission android:name="android.permission.INTERNET"/>
     <application
         android:usesCleartextTraffic="true"  <!-- for local HTTP only -->
         ...>
     ```

3. **Run**

   ```bash
   flutter run
   ```

4. **Set credentials**

   * Open **Settings** in the app and enter:

     * **Site URL** (e.g. `http://10.0.2.2:8888/wp1`)
     * **Username**
     * **Application Password**

---

## Security (client)

* Uses **WordPress Application Passwords** over HTTPS (recommended for production).
* Stores:

  * Site URL and username in shared preferences.
  * Password in **secure storage** (KeyStore / EncryptedSharedPreferences on Android).
* The plugin authenticates file-management operations but returns direct upload URLs. For stricter privacy, add web-server controls or an authenticated download layer that remains compatible with the client.

---

## REST Endpoints Used

* **Upload:** `POST {site}/wp-json/private-file-uploader/v1/upload`
  Body: `multipart/form-data` with field `file`

* **List:** `GET {site}/wp-json/private-file-uploader/v1/files`

* **Connection check:** `GET {site}/wp-json/private-file-uploader/v1/ping`

* **Rename:** `POST {site}/wp-json/private-file-uploader/v1/files/{filename}/rename`
  Body: JSON with field `new_name`

* **Delete:** `DELETE {site}/wp-json/private-file-uploader/v1/files/{filename}`

### Example list response

  ```json
  {
    "ok": true,
    "items": [
      {
        "name": "file.jpg",
        "url": "https://example.com/wp-content/uploads/.../file.jpg",
        "size": 12345,
        "mime": "image/jpeg",
        "modified": 1759845406
      }
    ],
    "total": 1
  }
  ```

---

## Project Structure (high-level)

```
lib/
  pages/
    home_page.dart        # file picker + upload + email prompt
    uploads_page.dart     # server-side list + copy URL
    settings_page.dart    # credentials & reset
    info_page.dart        # about & diagnostics
  services/
    app_storage.dart      # local prefs + secure storage (password), upload history
    wp_api.dart           # REST client for upload & list (Basic Auth)
  main.dart               # NavigationRail + SafeArea layout
```

---

## Roadmap

* Open file with system app on tap (optional).
* Better error feedback and status indicators in Uploads.
* Client-side pagination once the server exposes it.

---

## License

MIT — see `LICENSE`.
