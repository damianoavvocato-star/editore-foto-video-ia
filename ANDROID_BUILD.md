# Android build pipeline

Android project files are generated on the CI runner from the Flutter project:

```bash
flutter create --platforms=android --org com.editorefoto --project-name editore_foto_video_ia .
flutter pub get
flutter analyze
flutter test --reporter expanded
flutter build apk --release
```

The GitHub Actions workflow performs these steps with Java 17 and Flutter stable, then uploads `app-release.apk` as the `editore-foto-video-ia-android-apk` artifact. No APK should be considered validated until that workflow job completes successfully.


## Quality gate

The APK job depends on both `flutter-test` and `backend-test`. If either test
job fails, GitHub Actions skips the APK job, preventing an APK artifact from
being published from an unverified revision. Flutter analysis and unit tests
run once in the dedicated Flutter job; the Android job then generates the
platform scaffold and performs the release build.
