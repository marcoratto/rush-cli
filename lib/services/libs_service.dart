import 'package:get_it/get_it.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:collection/collection.dart';
import 'package:rush_cli/services/logger.dart';

import './file_service.dart';
import '../resolver/artifact.dart';
import '../utils/file_extension.dart';
import '../commands/deps/sync.dart';

const _devDeps = <String>{
  'androidx.appcompat:appcompat:1.0.0',
  'ch.acra:acra:4.9.0',
  'org.locationtech.jts:jts-core:1.16.1',
  'org.osmdroid:osmdroid-android:6.1.0',
  'redis.clients:jedis:3.1.0',
  'com.caverock:androidsvg:1.2.1',
  'com.firebase:firebase-client-android:2.5.2',
  'com.google.api-client:google-api-client:1.31.1',
  'com.google.api-client:google-api-client-android2:1.10.3-beta',
  'org.webrtc:google-webrtc:1.0.23995',
};

const _d8Coord = 'com.android.tools:r8:3.3.28';
const _pgCoord = 'com.guardsquare:proguard-base:7.2.2';
const _manifMergerAndDeps = <String>[
  'com.android.tools.build:manifest-merger:30.2.2',
  'org.w3c:dom:2.3.0-jaxb-1.0.6',
  'xml-apis:xml-apis:1.4.01',
];

const _kotlinGroupId = 'org.jetbrains.kotlin';

/// Kotlin version used by Rush's annotation processor.
const _rushApKotlinVersion = '1.7.10';

class LibService {
  static final _fs = GetIt.I<FileService>();
  static final _lgr = GetIt.I<Logger>();

  LibService._() {
    _lgr.dbg('Initializing Hive in ${_fs.rushHomeDir.path}/cache');
    Hive
      ..init(p.join(_fs.rushHomeDir.path, 'cache'))
      ..registerAdapter(ArtifactAdapter())
      ..registerAdapter(ScopeAdapter());
  }

  static Future<LibService> instantiate() async {
    _lgr.dbg('Instantiating LibService');
    final instance = LibService._();
    instance.devDepsBox = await Hive.openBox<Artifact>('dev-deps');
    instance._buildLibsBox = await Hive.openBox<Artifact>('build-libs');
    return instance;
  }

  late final Box<Artifact> devDepsBox;
  late final Box<Artifact> _buildLibsBox;

  List<String> devDepJars() => [
        for (final lib in devDepsBox.values) lib.classesJar,
        p.join(_fs.libsDir.path, 'android.jar'),
        p.join(_fs.libsDir.path, 'annotations.jar'),
        p.join(_fs.libsDir.path, 'runtime.jar'),
        p.join(_fs.libsDir.path, 'kawa-1.11-modified.jar'),
        p.join(_fs.libsDir.path, 'physicaloid-library.jar')
      ];

  String d8Jar() => _buildLibsBox.get(_d8Coord)!.classesJar;

  List<String> pgJars() =>
      _buildLibsBox.get(_pgCoord)!.classpathJars(_buildLibsBox.values).toList();

  List<String> manifMergerJars() => _manifMergerAndDeps
      .map((el) => _buildLibsBox.get(el)!.classpathJars(_buildLibsBox.values))
      .flattened
      .toList();

  List<String> kotlincJars() => _buildLibsBox
      .get('$_kotlinGroupId:kotlin-compiler-embeddable:$_rushApKotlinVersion')!
      .classpathJars(_buildLibsBox.values)
      .toList();

  String kotlinStdLib(String ktVersion) {
    return devDepsBox
        .get('$_kotlinGroupId:kotlin-stdlib:$ktVersion')!
        .classesJar;
  }

  List<String> kaptJars() => _buildLibsBox
      .get(
          '$_kotlinGroupId:kotlin-annotation-processing-embeddable:$_rushApKotlinVersion')!
      .classpathJars(_buildLibsBox.values)
      .toList();

  Future<void> ensureDevDeps() async {
    final resolutionNeeded = () {
      if (devDepsBox.isEmpty || _buildLibsBox.isEmpty) {
        return true;
      }
      return !(devDepsBox.values
              .every((el) => el.classesJar.asFile().existsSync()) &&
          _buildLibsBox.values
              .every((el) => el.classesJar.asFile().existsSync()));
    }();
    if (!resolutionNeeded) {
      _lgr.dbg('Dev-deps are up-to-date');
      return;
    }

    _lgr.dbg('Resolving dev-deps');
    await SyncSubCommand().sync(
        cacheBox: _buildLibsBox,
        saveCoordinatesAsKeys: true,
        coordinates: {
          Scope.runtime: [
            '$_kotlinGroupId:kotlin-compiler-embeddable:$_rushApKotlinVersion',
            '$_kotlinGroupId:kotlin-annotation-processing-embeddable:$_rushApKotlinVersion',
            _d8Coord,
            _pgCoord,
            ..._manifMergerAndDeps,
          ],
        });

    await SyncSubCommand()
        .sync(cacheBox: devDepsBox, saveCoordinatesAsKeys: true, coordinates: {
      Scope.compile: [..._devDeps, '$_kotlinGroupId:kotlin-stdlib:$_rushApKotlinVersion']
    });
  }
}
