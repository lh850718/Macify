import 'package:flutter_test/flutter_test.dart';
import 'package:huxi_zen/src/preferences/user_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('defaults zen cue audio switches to off', () async {
    SharedPreferences.setMockInitialValues({});

    final preferences = await UserPreferences.load();

    expect(preferences.settings.zenSound, isFalse);
    expect(preferences.settings.zenVoiceCue, isFalse);
  });

  test('saves and loads independent zen cue audio switches', () async {
    SharedPreferences.setMockInitialValues({});

    await UserPreferences.saveSettings(
      const AppSettings.defaults().copyWith(zenSound: true, zenVoiceCue: true),
    );
    final preferences = await UserPreferences.load();

    expect(preferences.settings.zenSound, isTrue);
    expect(preferences.settings.zenVoiceCue, isTrue);
  });

  test('migrates legacy voice cue mode to voice switch', () async {
    SharedPreferences.setMockInitialValues({
      'zen-sound-v1': true,
      'zen-cue-audio-mode-v1': 'voice',
    });

    final preferences = await UserPreferences.load();

    expect(preferences.settings.zenSound, isFalse);
    expect(preferences.settings.zenVoiceCue, isTrue);
  });

  test('migrates legacy bowl cue mode to bowl switch', () async {
    SharedPreferences.setMockInitialValues({
      'zen-sound-v1': true,
      'zen-cue-audio-mode-v1': 'bowl',
    });

    final preferences = await UserPreferences.load();

    expect(preferences.settings.zenSound, isTrue);
    expect(preferences.settings.zenVoiceCue, isFalse);
  });

  test('normalizes unknown zen cue audio mode to bowl', () {
    expect(normalizeZenCueAudioMode('unknown'), zenCueAudioModeBowl);
  });
}
