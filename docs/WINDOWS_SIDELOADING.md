# Build and install Folio from Windows

You can build Folio on GitHub's hosted Mac runner and install it on your iPhone using Sideloadly on Windows. Your iPhone must run **iOS 17 or later**.

The workflow creates `unsigned.ipa`; **Sideloadly signs it before installation**. Opening the unsigned file directly on your iPhone will not install it. You do not need a Mac, a paid Apple Developer membership, or Apple signing secrets in GitHub.

## 1. Upload this project to GitHub

1. Install [Git for Windows](https://git-scm.com/downloads/win) if needed.
2. Sign in to [GitHub](https://github.com/new) and create a repository named `folio`. Public or private is fine; hosted runner usage is subject to your account's Actions allowance. Leave **README**, **.gitignore**, and **license** initialization unchecked so the remote starts empty.
3. Open PowerShell in this project directory. Replace `YOUR_GITHUB_USERNAME` in the URL below with your GitHub username:

   ```powershell
   Set-Location -LiteralPath 'E:\vibe coding\dictionary'
   git init
   git branch -M main
   git add .
   git commit -m "Add Folio and unsigned IPA build workflow"
   git remote add origin https://github.com/YOUR_GITHUB_USERNAME/folio.git
   git push -u origin main
   ```

4. Complete Git's browser sign-in when prompted. If Git asks for a commit identity, configure your preferred name and email, then retry the commit and push:

   ```powershell
   git config user.name "Your Name"
   git config user.email "YOUR_GITHUB_COMMIT_EMAIL"
   ```

The commands above are for this workspace's initial upload; it currently has no Git repository. The checked-in `.gitignore` excludes local tools, build output, and IPA files. Commit the sources, resources, `Package.swift`, `Package.resolved`, `Folio.xcodeproj`, `Scripts`, and `.github` directory together.

## 2. Run the IPA build

The first push to `main` starts **Build unsigned IPA** automatically. Later pushes to `main` also rebuild it.

To request a fresh build manually:

1. Open your repository's **Actions** tab. Enable workflows if GitHub prompts you.
2. Select **Build unsigned IPA** in the workflow list.
3. Select **Run workflow**, choose `main`, and click **Run workflow** again.
4. Open the new run and wait for the **Build Folio for iPhone** job to turn green.

The manual trigger becomes available once the workflow exists on the repository's default branch. These controls require write access. See [GitHub's manual workflow guide](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow).

The separate **Swift and iOS checks** workflow runs tests. Choose **Build unsigned IPA** to obtain the installer. A failure in the separate test workflow does not stop the IPA job; review its failures before relying on the app.

## 3. Download the installer

1. Open the successful **Build unsigned IPA** run's summary page.
2. Scroll to **Artifacts** and click **folio-unsigned-ipa** while signed in to GitHub.
3. Extract the downloaded ZIP using Windows **Extract All**. Inside it is `unsigned.ipa`.
4. Keep `unsigned.ipa` intact. Load this file into Sideloadly; do not extract the IPA itself or use the outer artifact ZIP as the installer.

The workflow retains artifacts for 14 days, subject to repository retention settings. Run the workflow again if the artifact has expired. See [GitHub's artifact download instructions](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/download-workflow-artifacts).

The IPA's internal layout is:

```text
unsigned.ipa
└── Payload/
    └── Folio.app/
        ├── Folio
        ├── Info.plist
        └── assets and bundled resources
```

## 4. Install with Sideloadly on Windows

1. Download and install [Sideloadly from its official website](https://sideloadly.io/). Use that site's Windows setup links for the web versions of **iTunes** and **iCloud**; Sideloadly currently requests these instead of the Microsoft Store versions.
2. Connect your iPhone with a USB data cable, unlock it, and tap **Trust This Computer** when prompted. Confirm Windows/iTunes detects the phone.
3. Open Sideloadly and choose your connected iPhone from the device list.
4. Drag `unsigned.ipa` onto Sideloadly's IPA area, or use its file picker.
5. Enter your Apple ID in Sideloadly. Leave Apple ID signing enabled, click **Start**, and complete its password and two-factor authentication prompts.
6. Wait for signing and installation to finish. Apple credentials belong in Sideloadly's local sign-in flow; the workflow does not request them.
7. If iOS reports an untrusted developer, open **Settings → General → VPN & Device Management**, select your developer profile, and follow the trust/verification prompts. Menu wording can vary with iOS.
8. If iOS requests Developer Mode, enable it under **Settings → Privacy & Security → Developer Mode**, restart the phone, and confirm enabling it after restart. Apple's [Developer Mode guide](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device) describes this process. If the toggle is missing, finish pairing/installing the developer-signed app first and check again.
9. Open **Folio** on your iPhone. Save a sample word, then open **Practice** to try the first review.

Sideloadly's supported setup, signing, and refresh behavior is documented on its [download page](https://sideloadly.io/) and [FAQ](https://sideloadly.io/faq). Developer profile verification instructions also appear in its [installation FAQ](https://sideloadly.io/faq.html).

## 5. Refresh and update without losing vocabulary

A free Apple ID normally signs an app for **7 days** and is limited to **3 sideloaded apps** at once. Re-sign Folio before expiry, or use Sideloadly's automatic refresh feature while its daemon can reach your connected phone. Wi-Fi refresh requires initial USB pairing and Wi-Fi sync setup. See the [Sideloadly FAQ](https://sideloadly.io/faq).

For an app update:

```powershell
git add .
git commit -m "Update Folio"
git push
```

Download the new successful build's `unsigned.ipa` and install it **over the existing Folio app**, using the **same Apple ID and the same effective bundle identifier** in Sideloadly. Keep any custom bundle identifier unchanged. Sideloadly documents this as the way to overwrite an app while keeping local data. **Do not uninstall Folio between updates:** its vocabulary and review history live in the app's local storage. See [Sideloadly's update and local-progress FAQ](https://sideloadly.io/faq).

## If something fails

| Symptom | Next step |
| --- | --- |
| No Run workflow button | Check that `.github/workflows/build-ipa.yml` is on the default branch and Actions is enabled. |
| Build job is red | Open the failed step and find the first compiler/build error. If available, download **folio-device-build-log**. An IPA is uploaded only after a successful device build and package verification. |
| No IPA artifact | Check the **Build unsigned IPA** workflow, rather than the test workflow. A cancelled or failed build may have no installer. |
| Sideloadly cannot detect the phone | Unlock the phone, trust the PC, try another data cable, and confirm iTunes detects it. Check the official Sideloadly setup requirements. |
| Untrusted developer / Developer Mode alert | Follow the iPhone trust and Developer Mode steps above. |
| App stops opening after several days | Refresh/re-sign it using the same Apple ID and bundle identifier. |
| Free-account app limit reached | Free accounts allow three sideloaded apps; check the Sideloadly FAQ before removing any app whose local data you need. |

## What the workflow does

`.github/workflows/build-ipa.yml` uses `macos-15` and its selected Xcode, builds the **Folio** scheme in **Release** for `generic/platform=iOS` with the `iphoneos` SDK and arm64 architecture, and disables code signing. It copies the complete device app into `Payload/Folio.app`, zips that directory into `unsigned.ipa`, checks the archive and device metadata, and uploads **folio-unsigned-ipa**.

This packaging path does not use `xcodebuild -exportArchive`, a dummy team, or a provisioning profile. Sideloadly supplies signing and provisioning on Windows. The repository also keeps its existing simulator test workflow.

The workflow and packaging commands can be inspected locally, but the first actual Apple SDK device build must run on GitHub's hosted Mac. There is no prebuilt IPA bundled in this repository.
