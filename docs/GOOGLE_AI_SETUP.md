# Technical Room Google AI setup

The app code is ready for configuration, but this repository has no live Google project, OAuth client IDs, Gemini API key, or deployed recognition endpoint. A Google login button cannot authenticate until those resources exist. Offline scans, photos and geometry detection do not require them.

## User workflow

1. Start **Scan Technik Room**. House scanning remains separate.
   Capture uses native navigation and grouped system controls. Manual tools, alignment and diagnostics are disclosed separately. You can save a raw scan/photos without setting alignment; placing manual survey annotations still requires its checkpoint verification.
2. Open **Profile → Google account / AI & photo connections (Mac: Settings → Google account & AI)** to sign in and configure the service URL. Turn on **Google AI mode** before or during scanning. Selected colour images and matching LiDAR depth are captured automatically as you move. Images remain local. Scan/review/photo screens show connection status only; they do not launch login or edit connection settings.
3. Optionally tap **Take photo** for a detail you want to pin to the saved model. This also works with AI mode off.
4. Save the scan. Open **MEP review**, select up to five images and confirm **Send selected images and analyse**. The app sends only those images to the configured service. LiDAR geometry stays on-device.
5. Gemini returns image regions for straight pipes, round ducts and rectangular ducts. The app projects those regions into depth, fits geometric candidates and lets you inspect, edit, accept or reject them. DN, medium, hidden connections and engineering accuracy are not inferred.
6. In **3D scan**, choose Scan / MEP / Both. Turn on **Photos** to show camera-position markers. Tap a marker or its numbered photo button to view the local photograph.
7. **Copy to Google Photos** is optional and asks for separate Photos upload permission. The app stores the resulting private Google Photos link alongside the local photo. It never makes a public sharing link or deletes the local photo.

Older surveys with only frame metadata cannot supply camera images for Gemini. Local geometry detection still works on their mesh. Recognition needs adequate depth and visible surfaces; it may return no 3D candidate when an image region cannot be fitted reliably.

## 1. Create the Google project and OAuth clients

Use a Google Cloud project you own. Firebase is not required for this implementation.

- Configure the OAuth consent screen, app support information and test users. While in testing, add the accounts you will use.
- Create an **iOS OAuth client** for bundle ID `io.github.itsmebablu.dwalkscan.localtest` (the current iPhone scheme). Register a different client if you change the bundle ID.
- For Mac sign-in, Google's current guide also uses an **iOS-type OAuth client**, registered for bundle ID `io.github.itsmebablu.dwalkscan`. The Mac target includes the required app keychain access group. Use an Apple-signed build for actual credential storage.
- Create a **Web application OAuth client** for the backend audience. Its client ID becomes the app's `GIDServerClientID` and the backend's `GOOGLE_SERVER_CLIENT_ID`.
- Enable the **Google Photos Library API** if you want Photos copying. The app requests only `https://www.googleapis.com/auth/photoslibrary.appendonly` when a user explicitly copies a photo. Testing restrictions or Google verification requirements may apply before wider distribution.
- Do not put a Gemini API key or OAuth client secret into the app. Native client IDs are public configuration, not API keys.

Official references: [Google sign-in setup](https://developers.google.com/identity/sign-in/ios/start-integrating), [backend ID-token verification](https://developers.google.com/identity/sign-in/ios/backend-auth), [Google Photos uploads](https://developers.google.com/photos/library/guides/upload-media).

## 2. Configure the app locally

Create `Config/GoogleAI.local.xcconfig` (ignored by Git):

```xcconfig
DWALK_GOOGLE_CLIENT_ID[sdk=iphone*] = YOUR_IOS_CLIENT_ID.apps.googleusercontent.com
DWALK_GOOGLE_REVERSED_CLIENT_ID[sdk=iphone*] = com.googleusercontent.apps.YOUR_IOS_CLIENT_ID
DWALK_GOOGLE_CLIENT_ID[sdk=macosx*] = YOUR_MAC_CLIENT_ID.apps.googleusercontent.com
DWALK_GOOGLE_REVERSED_CLIENT_ID[sdk=macosx*] = com.googleusercontent.apps.YOUR_MAC_CLIENT_ID
DWALK_GOOGLE_SERVER_CLIENT_ID = YOUR_WEB_CLIENT_ID.apps.googleusercontent.com
// $() avoids xcconfig interpreting the second slash as a comment.
DWALK_GOOGLE_AI_SERVICE_URL = https:/$()/YOUR_SERVICE_HOST
```

Replace the entire example IDs with Google's actual values. The redirect scheme is the native client ID with its dot-separated components reversed. The app validates that its redirect scheme is registered before invoking the SDK, avoiding a crash from incomplete configuration.

Run `xcodegen generate`, then build normally in Xcode. Alternatively override the four `DWALK_GOOGLE_*` build settings for a one-off build. The checked-in default is deliberately unconfigured. Users can also set the HTTPS recognition service URL under MEP review → Connection settings. Provider keys and Google access tokens are never stored in UserDefaults.

## 3. Configure Gemini's free tier

Create a Gemini API key in Google AI Studio for a project without paid Gemini billing enabled. Choose a currently available image-understanding model with free-tier access in **your** project, and set its exact model ID as `GEMINI_MODEL` on the backend. No model ID or quota is assumed in the app.

This implementation has no subscription, payment or pricing UI. It does not enable billing, create cloud resources, automatically switch to a paid model or retry provider quota failures. Free quota depends on Google's project/model availability. Google sign-in does **not** give each app user their own Gemini quota: calls use the server's project.

The backend's request counters are additional prototype limits, not a billing guarantee. Check [Google's active project limits](https://ai.google.dev/gemini-api/docs/rate-limits) and [free-tier/model terms](https://ai.google.dev/gemini-api/docs/pricing), including the data-processing terms applicable to your region and customer images.

## 4. Run the backend for development

The separate service lives in `services/technical-google-ai/`; it never imports or changes House scan code. It needs Python 3.12+ and the dependencies in `requirements.txt`.

```sh
cd services/technical-google-ai
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
```

Copy `.env.example` to `.env` and fill it locally. Keep it out of Git. Supply the same Web/server OAuth client ID as the app, your Gemini key, an available free-tier model and an explicit email allowlist. Set `GEMINI_FREE_PROJECT_CONFIRMED=true` only after checking your project's billing/model setup.

Export those variables in your terminal or load them with your deployment platform's secret/environment configuration. Then run:

```sh
.venv/bin/uvicorn app:app --host 127.0.0.1 --port 8080 --workers 1 --no-access-log
```

The iPhone needs a trusted **HTTPS** URL reachable from the device. `localhost` on the iPhone is not your Mac. For development, use a secure HTTPS reverse proxy/tunnel to this local service. The app does not disable transport security or accept self-signed certificates. A tunnel exposes a service endpoint; requests still need a valid Google ID token and an allowlisted account.

Run backend contract tests without a Google key or any AI requests:

```sh
.venv/bin/pip install -r requirements-dev.txt
.venv/bin/python -m unittest -v test_app.py
```

## 5. Hosting later

Recommended hosted destination: **Google Cloud Run**, using the provided Dockerfile, request-based instances, minimum instances zero and an initial maximum of one instance. Configure Google identity and Gemini secrets on the service. The API is reachable over HTTPS; application-level Google ID-token verification protects `/v1/segment`. Do not rely solely on the `/health` endpoint.

Cloud Run requires a billing account and its free allowance does not guarantee zero charges. No deployment or billing setup has been performed by this change. The backend can stay on your Mac until you choose hosting.

If you later use Cloud Run while keeping Gemini on free quota, use a **separate hosting project** for Cloud Run and leave the Gemini API-key project unbilled. Do not enable billing on the Gemini project merely to host the backend. The hosting service can verify the OAuth project's Web client ID and call Gemini with that separate project's key.

The SQLite counter/cache is suitable for a single local prototype. Cloud Run's filesystem is ephemeral; counters/cache can reset on restarts and are not shared across instances. Before public multi-instance use, move them to persistent shared storage, define user access policy, and set provider/project quota controls. Do not treat the current counters as a monetary spending cap.

## Data, limits and validation

- Up to 32 paired image/depth viewpoints and a 48 MiB in-memory evidence budget. Automatic viewpoints can be replaced when full. Explicitly taken photos are pinned; if all capacity is pinned, new photos fail visibly rather than deleting old ones.
- `evidence.json` holds calibration/depth metadata; `capture-images/<UUID>.jpg` holds image bytes. `recognition.json` holds reviewable candidates in original AR-session coordinates. Optional sidecars preserve reading of older packages. The original manual Technical Room v1 schema stays unchanged.
- Only selected image bytes, image hash and requested mask size go to the recognition service. Depth, room measurements and the full scan are not sent. The service verifies Google's signed ID token/audience and a verified-email allowlist before accepting images.
- The backend does not store original images. It stores bounded segmentation results keyed by user, model and image hash plus prototype request counters. The selected AI provider processes the images under its terms.
- Returned categories, polygon sizes, image hashes, frame IDs, mask dimensions and run lengths are validated. Low-confidence depth is excluded. Local fitting must find supporting geometry; an AI label alone does not create a 3D object.
- Cylinder fitting splits unsupported gaps. Rectangular ducts require two perpendicular visible faces. Dimensions are estimates of visible outer surfaces, possibly insulation, and remain unverified.
- Accepted/rejected candidates are kept separately from raw observations. Re-running the detector suppresses matching candidates rather than resurrecting rejected objects. Material presets are user-selected appearances; the app does not claim to identify physical material from colour.
- Physical acceptance remains necessary: new scan → AI-mode image retention → save/reopen → photo marker tap → Google sign-in → selected-image analysis → candidate review → Google Photos upload → signed-in private link. No real Google request or cloud upload can be validated without your configured project.
- Mac UI validation completed for importing the earlier phone survey, opening its 3D viewer/MEP form, running offline candidate detection, and safely showing the missing-Google-configuration notice. This does not validate the candidate's semantic identity or measurement accuracy.
