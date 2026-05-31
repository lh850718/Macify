import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huxi_zen/src/app.dart';
import 'package:huxi_zen/src/content/content_models.dart';
import 'package:huxi_zen/src/content/content_repository.dart';
import 'package:huxi_zen/src/content/remote_content_sync.dart';
import 'package:huxi_zen/src/media/media_resource_resolver.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('shows the content-driven home shell', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      const HuxiZenApp(
        repository: _FakeContentRepository(),
        loadRemoteImages: false,
        bundledMediaCatalog: MediaResourceCatalog.empty(),
      ),
    );
    await tester.pump();

    expect(find.text('落日湖岛'), findsOneWidget);
    expect(find.text('···'), findsOneWidget);
    expect(find.text('♪'), findsOneWidget);
    expect(find.text('--° 天气加载中'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('open-settings-button')));
    await tester.pumpAndSettle();

    expect(find.text('显示'), findsOneWidget);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -520));
    await tester.pumpAndSettle();

    expect(find.text('播放范围'), findsOneWidget);
    expect(find.text('全部'), findsOneWidget);
    expect(find.text('收藏'), findsOneWidget);
  });

  testWidgets('custom ambient mix exposes percentage sliders', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      const HuxiZenApp(
        repository: _FakeContentRepository(),
        loadRemoteImages: false,
        bundledMediaCatalog: MediaResourceCatalog.empty(),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('open-settings-button')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('视频背景音'),
      420,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, '自定义混音'));
    await tester.pumpAndSettle();

    expect(find.text('0/5'), findsOneWidget);
    final forestButton = find.byKey(
      const ValueKey('custom-ambient-track-forest'),
    );
    await tester.scrollUntilVisible(
      forestButton,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(forestButton);
    await tester.pump();
    expect(find.text('0%'), findsOneWidget);

    final forestSlider = tester.widget<Slider>(
      find.byKey(const ValueKey('custom-ambient-volume-forest')),
    );
    forestSlider.onChanged!(54);
    await tester.pump();
    expect(find.text('54%'), findsOneWidget);

    final birdsButton = find.byKey(
      const ValueKey('custom-ambient-track-birds'),
    );
    await tester.scrollUntilVisible(
      birdsButton,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(birdsButton);
    await tester.pump();
    final birdsSlider = tester.widget<Slider>(
      find.byKey(const ValueKey('custom-ambient-volume-birds')),
    );
    birdsSlider.onChanged!(15);
    await tester.pump();
    expect(find.text('15%'), findsOneWidget);

    await tester.tap(find.text('保存返回'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('ambient-audio-mode-v1'), 'custom');
    expect(
      prefs.getStringList('custom-ambient-mix-v1'),
      containsAll(['forest|0.5400', 'birds|0.1500']),
    );
  });

  testWidgets('starts optional remote content check after local load', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    RemoteContentCheck? receivedCheck;

    await tester.pumpWidget(
      HuxiZenApp(
        repository: const _FakeContentRepository(),
        loadRemoteImages: false,
        contentSyncService: const _FakeContentSyncService(),
        bundledMediaCatalog: const MediaResourceCatalog.empty(),
        remoteManifestUri: Uri.parse(
          'https://example.com/content-manifest.json',
        ),
        onRemoteContentCheck: (check) => receivedCheck = check,
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });

    expect(receivedCheck, isNotNull);
    expect(receivedCheck!.contentVersionChanged, isTrue);
    expect(receivedCheck!.changedFiles, ['videos.json']);
  });

  testWidgets('opens breathing overlay and starts custom exercise countdown', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      const HuxiZenApp(
        repository: _FakeContentRepository(),
        loadRemoteImages: false,
        bundledMediaCatalog: MediaResourceCatalog.empty(),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('open-breathing-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('吸气'), findsOneWidget);
    expect(find.text('触感'), findsOneWidget);
    expect(find.text('颂钵音'), findsOneWidget);
    expect(find.text('自定义练习'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('start-custom-breath-button')));
    await tester.pump();

    expect(find.text('3'), findsOneWidget);
    expect(find.textContaining('本次练习8组'), findsOneWidget);
    expect(find.textContaining('吸4秒->屏息7秒->呼8秒'), findsOneWidget);
    expect(find.textContaining('4-7-8-0-8'), findsNothing);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('2'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('1'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('吸气'), findsOneWidget);
    expect(find.text('还剩8组'), findsNothing);
    await tester.pump(const Duration(milliseconds: 760));
    expect(find.text('还剩8组'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('backgrounding breathing resumes without restoring bowl sound', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'remember-zen-cues-v1': true,
      'zen-haptics-v1': true,
      'zen-sound-v1': true,
    });

    await tester.pumpWidget(
      const HuxiZenApp(
        repository: _FakeContentRepository(),
        loadRemoteImages: false,
        bundledMediaCatalog: MediaResourceCatalog.empty(),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('open-breathing-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('吸气'), findsOneWidget);
    expect(find.text('颂钵音'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });

    expect(find.text('颂钵音'), findsNothing);
    final pausedPrefs = await SharedPreferences.getInstance();
    expect(pausedPrefs.getBool('zen-haptics-v1'), isTrue);
    expect(pausedPrefs.getBool('zen-sound-v1'), isFalse);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('吸气'), findsOneWidget);
    expect(find.text('颂钵音'), findsOneWidget);
    final resumedPrefs = await SharedPreferences.getInstance();
    expect(resumedPrefs.getBool('zen-haptics-v1'), isTrue);
    expect(resumedPrefs.getBool('zen-sound-v1'), isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _FakeContentRepository implements ContentRepository {
  const _FakeContentRepository();

  @override
  Future<ContentBundle> load() async {
    return const ContentBundle(
      manifest: ContentManifest(
        schemaVersion: 1,
        contentVersion: 'test',
        defaultVideoLibrary: 'premiumFreeAerial',
        files: {},
      ),
      config: ContentConfig(
        schemaVersion: 1,
        contentVersion: 'test',
        defaultVideoLibrary: 'premiumFreeAerial',
        defaultVideoBase: 'https://example.com/macify-premium',
        defaultAmbientAudioBase: 'https://example.com/macify-audio',
      ),
      videos: [
        VideoItem(
          id: 'lake',
          name: 'Lake',
          displayName: '落日湖岛',
          locationName: '湖泊',
          locationCountry: '',
          sourceName: 'Mixkit',
          sourcePage: '',
          sourceDownloadPage: '',
          url: '',
          previewImage: '',
          category: 'Landscapes',
          subcategories: ['Lake'],
          tags: ['lake'],
          timeOfDay: 'Sunset',
          description: '湖面与暮色安静铺开。',
          sourceResolution: '4K',
          duration: '0:20',
          license: 'Test License',
          attribution: '',
          licenseNotes: '',
          qualityTier: 'published',
        ),
      ],
      ambientCatalog: AmbientCatalog(
        modes: {'VIDEO': 'video', 'CUSTOM': 'custom'},
        maxCustomAmbientTracks: 5,
        tracks: {
          'forest': AmbientTrack(
            id: 'forest',
            label: '森林',
            file: 'forest-ambience.mp3',
            durationMs: 212976,
            volume: 0.54,
          ),
          'birds': AmbientTrack(
            id: 'birds',
            label: '鸟鸣',
            file: 'birds.mp3',
            durationMs: 180000,
            volume: 0.62,
          ),
        },
        customTrackIds: ['forest', 'birds'],
        customLabels: {'forest': '森林', 'birds': '鸟鸣'},
      ),
      ambientRules: [],
      videoAudioMixes: [],
    );
  }
}

class _FakeContentSyncService implements ContentSyncService {
  const _FakeContentSyncService();

  @override
  Future<RemoteContentCheck> checkManifest({
    required ContentManifest localManifest,
    required Uri remoteManifestUri,
  }) async {
    return RemoteContentCheck.compare(
      localManifest: localManifest,
      remoteManifest: const ContentManifest(
        schemaVersion: 1,
        contentVersion: 'remote-test',
        defaultVideoLibrary: 'premiumFreeAerial',
        files: {'videos.json': ManifestFile(bytes: 1, sha256: 'remote')},
      ),
    );
  }
}
