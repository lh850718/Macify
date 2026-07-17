import 'package:shared_preferences/shared_preferences.dart';

import '../content/content_models.dart';
import '../features/breathing/breathing_models.dart';

const zenCueAudioModeBowl = 'bowl';
const zenCueAudioModeVoice = 'voice';

class UserPreferences {
  const UserPreferences({
    required this.favoriteKeys,
    required this.shuffleScope,
    required this.settings,
  });

  static const _favoriteKeysKey = 'favorite-video-keys-v1';
  static const _shuffleScopeKey = 'shuffle-scope-v1';
  static const _showClockKey = 'show-clock-v1';
  static const _showWeatherKey = 'show-weather-v1';
  static const _showQuoteKey = 'show-quote-v1';
  static const _showVideoMetaKey = 'show-video-meta-v1';
  static const _rememberZenCuesKey = 'remember-zen-cues-v1';
  static const _zenHapticsKey = 'zen-haptics-v1';
  static const _zenSoundKey = 'zen-sound-v1';
  static const _zenVoiceCueKey = 'zen-voice-cue-v1';
  static const _zenCueAudioModeKey = 'zen-cue-audio-mode-v1';
  static const _cityKey = 'weather-city-v1';
  static const _temperatureUnitKey = 'temperature-unit-v1';
  static const _ambientAudioModeKey = 'ambient-audio-mode-v1';
  static const _customAmbientMixKey = 'custom-ambient-mix-v1';
  static const _defaultBreathInhaleKey = 'default-breath-inhale-v1';
  static const _defaultBreathHoldInhaleKey = 'default-breath-hold-inhale-v1';
  static const _defaultBreathExhaleKey = 'default-breath-exhale-v1';
  static const _defaultBreathHoldExhaleKey = 'default-breath-hold-exhale-v1';
  static const _customBreathInhaleKey = 'custom-breath-inhale-v1';
  static const _customBreathHoldInhaleKey = 'custom-breath-hold-inhale-v1';
  static const _customBreathExhaleKey = 'custom-breath-exhale-v1';
  static const _customBreathHoldExhaleKey = 'custom-breath-hold-exhale-v1';
  static const _customBreathCyclesKey = 'custom-breath-cycles-v1';

  final Set<String> favoriteKeys;
  final String shuffleScope;
  final AppSettings settings;

  static Future<UserPreferences> load() async {
    final prefs = await SharedPreferences.getInstance();
    final storedZenSound = prefs.getBool(_zenSoundKey) ?? false;
    final legacyCueMode = normalizeZenCueAudioMode(
      prefs.getString(_zenCueAudioModeKey),
    );
    final hasVoiceCuePreference = prefs.containsKey(_zenVoiceCueKey);
    final zenSound = hasVoiceCuePreference
        ? storedZenSound
        : legacyCueMode == zenCueAudioModeVoice
        ? false
        : storedZenSound;
    final zenVoiceCue = hasVoiceCuePreference
        ? prefs.getBool(_zenVoiceCueKey) ?? false
        : legacyCueMode == zenCueAudioModeVoice && storedZenSound;
    return UserPreferences(
      favoriteKeys: (prefs.getStringList(_favoriteKeysKey) ?? const []).toSet(),
      shuffleScope: prefs.getString(_shuffleScopeKey) ?? 'all',
      settings: AppSettings(
        showClock: prefs.getBool(_showClockKey) ?? true,
        showWeather: prefs.getBool(_showWeatherKey) ?? true,
        showQuote: prefs.getBool(_showQuoteKey) ?? true,
        showVideoMeta: prefs.getBool(_showVideoMetaKey) ?? true,
        rememberZenCues: prefs.getBool(_rememberZenCuesKey) ?? false,
        zenHaptics: prefs.getBool(_zenHapticsKey) ?? false,
        zenSound: zenSound,
        zenVoiceCue: zenVoiceCue,
        city: prefs.getString(_cityKey) ?? '北京',
        temperatureUnit: prefs.getString(_temperatureUnitKey) ?? 'celsius',
        ambientAudioMode: prefs.getString(_ambientAudioModeKey) ?? 'video',
        customAmbientMix: _customAmbientMixPreference(
          prefs.getStringList(_customAmbientMixKey) ?? const [],
        ),
        defaultBreathRhythm: BreathingRhythm(
          inhaleSeconds: _intPreference(
            prefs,
            _defaultBreathInhaleKey,
            const BreathingRhythm.defaultBreath().inhaleSeconds,
            min: 1,
            max: 60,
          ),
          holdAfterInhaleSeconds: _intPreference(
            prefs,
            _defaultBreathHoldInhaleKey,
            const BreathingRhythm.defaultBreath().holdAfterInhaleSeconds,
            min: 0,
            max: 60,
          ),
          exhaleSeconds: _intPreference(
            prefs,
            _defaultBreathExhaleKey,
            const BreathingRhythm.defaultBreath().exhaleSeconds,
            min: 1,
            max: 60,
          ),
          holdAfterExhaleSeconds: _intPreference(
            prefs,
            _defaultBreathHoldExhaleKey,
            const BreathingRhythm.defaultBreath().holdAfterExhaleSeconds,
            min: 0,
            max: 60,
          ),
        ),
        customBreathRhythm: BreathingRhythm(
          inhaleSeconds: _intPreference(
            prefs,
            _customBreathInhaleKey,
            const BreathingRhythm.defaultExercise().inhaleSeconds,
            min: 1,
            max: 60,
          ),
          holdAfterInhaleSeconds: _intPreference(
            prefs,
            _customBreathHoldInhaleKey,
            const BreathingRhythm.defaultExercise().holdAfterInhaleSeconds,
            min: 0,
            max: 60,
          ),
          exhaleSeconds: _intPreference(
            prefs,
            _customBreathExhaleKey,
            const BreathingRhythm.defaultExercise().exhaleSeconds,
            min: 1,
            max: 60,
          ),
          holdAfterExhaleSeconds: _intPreference(
            prefs,
            _customBreathHoldExhaleKey,
            const BreathingRhythm.defaultExercise().holdAfterExhaleSeconds,
            min: 0,
            max: 60,
          ),
          cycles: _intPreference(
            prefs,
            _customBreathCyclesKey,
            const BreathingRhythm.defaultExercise().cycles,
            min: 1,
            max: 99,
          ),
        ),
      ),
    );
  }

  static Future<void> saveFavoriteKeys(Set<String> keys) async {
    final prefs = await SharedPreferences.getInstance();
    final sorted = keys.toList(growable: false)..sort();
    await prefs.setStringList(_favoriteKeysKey, sorted);
  }

  static Future<void> saveShuffleScope(String scope) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_shuffleScopeKey, scope);
  }

  static Future<void> saveSettings(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setBool(_showClockKey, settings.showClock),
      prefs.setBool(_showWeatherKey, settings.showWeather),
      prefs.setBool(_showQuoteKey, settings.showQuote),
      prefs.setBool(_showVideoMetaKey, settings.showVideoMeta),
      prefs.setBool(_rememberZenCuesKey, settings.rememberZenCues),
      prefs.setBool(_zenHapticsKey, settings.zenHaptics),
      prefs.setBool(_zenSoundKey, settings.zenSound),
      prefs.setBool(_zenVoiceCueKey, settings.zenVoiceCue),
      prefs.setString(_cityKey, settings.city),
      prefs.setString(_temperatureUnitKey, settings.temperatureUnit),
      prefs.setString(_ambientAudioModeKey, settings.ambientAudioMode),
      prefs.setStringList(
        _customAmbientMixKey,
        _encodeCustomAmbientMix(settings.customAmbientMix),
      ),
      prefs.setInt(
        _defaultBreathInhaleKey,
        settings.defaultBreathRhythm.inhaleSeconds,
      ),
      prefs.setInt(
        _defaultBreathHoldInhaleKey,
        settings.defaultBreathRhythm.holdAfterInhaleSeconds,
      ),
      prefs.setInt(
        _defaultBreathExhaleKey,
        settings.defaultBreathRhythm.exhaleSeconds,
      ),
      prefs.setInt(
        _defaultBreathHoldExhaleKey,
        settings.defaultBreathRhythm.holdAfterExhaleSeconds,
      ),
      prefs.setInt(
        _customBreathInhaleKey,
        settings.customBreathRhythm.inhaleSeconds,
      ),
      prefs.setInt(
        _customBreathHoldInhaleKey,
        settings.customBreathRhythm.holdAfterInhaleSeconds,
      ),
      prefs.setInt(
        _customBreathExhaleKey,
        settings.customBreathRhythm.exhaleSeconds,
      ),
      prefs.setInt(
        _customBreathHoldExhaleKey,
        settings.customBreathRhythm.holdAfterExhaleSeconds,
      ),
      prefs.setInt(_customBreathCyclesKey, settings.customBreathRhythm.cycles),
    ]);
  }
}

class AppSettings {
  const AppSettings({
    required this.showClock,
    required this.showWeather,
    required this.showQuote,
    required this.showVideoMeta,
    required this.rememberZenCues,
    required this.zenHaptics,
    required this.zenSound,
    required this.zenVoiceCue,
    required this.city,
    required this.temperatureUnit,
    required this.ambientAudioMode,
    required this.customAmbientMix,
    required this.defaultBreathRhythm,
    required this.customBreathRhythm,
  });

  const AppSettings.defaults()
    : showClock = true,
      showWeather = true,
      showQuote = true,
      showVideoMeta = true,
      rememberZenCues = false,
      zenHaptics = false,
      zenSound = false,
      zenVoiceCue = false,
      city = '北京',
      temperatureUnit = 'celsius',
      ambientAudioMode = 'video',
      customAmbientMix = const [],
      defaultBreathRhythm = const BreathingRhythm.defaultBreath(),
      customBreathRhythm = const BreathingRhythm.defaultExercise();

  final bool showClock;
  final bool showWeather;
  final bool showQuote;
  final bool showVideoMeta;
  final bool rememberZenCues;
  final bool zenHaptics;
  final bool zenSound;
  final bool zenVoiceCue;
  final String city;
  final String temperatureUnit;
  final String ambientAudioMode;
  final List<CustomAmbientSetting> customAmbientMix;
  final BreathingRhythm defaultBreathRhythm;
  final BreathingRhythm customBreathRhythm;

  AppSettings copyWith({
    bool? showClock,
    bool? showWeather,
    bool? showQuote,
    bool? showVideoMeta,
    bool? rememberZenCues,
    bool? zenHaptics,
    bool? zenSound,
    bool? zenVoiceCue,
    String? city,
    String? temperatureUnit,
    String? ambientAudioMode,
    List<CustomAmbientSetting>? customAmbientMix,
    BreathingRhythm? defaultBreathRhythm,
    BreathingRhythm? customBreathRhythm,
  }) {
    return AppSettings(
      showClock: showClock ?? this.showClock,
      showWeather: showWeather ?? this.showWeather,
      showQuote: showQuote ?? this.showQuote,
      showVideoMeta: showVideoMeta ?? this.showVideoMeta,
      rememberZenCues: rememberZenCues ?? this.rememberZenCues,
      zenHaptics: zenHaptics ?? this.zenHaptics,
      zenSound: zenSound ?? this.zenSound,
      zenVoiceCue: zenVoiceCue ?? this.zenVoiceCue,
      city: city ?? this.city,
      temperatureUnit: temperatureUnit ?? this.temperatureUnit,
      ambientAudioMode: ambientAudioMode ?? this.ambientAudioMode,
      customAmbientMix: customAmbientMix ?? this.customAmbientMix,
      defaultBreathRhythm: defaultBreathRhythm ?? this.defaultBreathRhythm,
      customBreathRhythm: customBreathRhythm ?? this.customBreathRhythm,
    );
  }
}

String normalizeZenCueAudioMode(String? value) {
  return value == zenCueAudioModeVoice
      ? zenCueAudioModeVoice
      : zenCueAudioModeBowl;
}

List<CustomAmbientSetting> _customAmbientMixPreference(List<String> raw) {
  final result = <CustomAmbientSetting>[];
  for (final item in raw) {
    final separator = item.lastIndexOf('|');
    if (separator <= 0 || separator >= item.length - 1) continue;
    final trackId = item.substring(0, separator).trim();
    final volume = double.tryParse(item.substring(separator + 1));
    if (trackId.isEmpty || volume == null || !volume.isFinite) continue;
    if (result.any((track) => track.trackId == trackId)) continue;
    result.add(
      CustomAmbientSetting(
        trackId: trackId,
        volume: volume.clamp(0, 1).toDouble(),
      ),
    );
  }
  return List.unmodifiable(result);
}

List<String> _encodeCustomAmbientMix(List<CustomAmbientSetting> mix) {
  return mix
      .map(
        (item) =>
            '${item.trackId}|${item.volume.clamp(0, 1).toStringAsFixed(4)}',
      )
      .toList(growable: false);
}

int _intPreference(
  SharedPreferences prefs,
  String key,
  int fallback, {
  required int min,
  required int max,
}) {
  final value = prefs.getInt(key) ?? fallback;
  return value.clamp(min, max).toInt();
}
