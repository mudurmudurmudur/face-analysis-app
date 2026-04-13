import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:ui' as ui;
import 'package:google_mlkit_face_mesh_detection/google_mlkit_face_mesh_detection.dart';
import 'package:flutter/painting.dart';
import 'dart:math' as math;



void main() {
  runApp(const StyleRehberiApp());
}

class StyleRehberiApp extends StatelessWidget {
  const StyleRehberiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Stil Rehberi',
      theme: ThemeData(
        useMaterial3: true,
      ),
      initialRoute: Routes.onboarding,
      routes: {
        Routes.onboarding: (_) => const OnboardingScreen(),
        Routes.photoGuide: (_) => const PhotoGuideScreen(),
        Routes.photoPick: (_) => const PhotoPickScreen(),
        Routes.loading: (_) => const LoadingScreen(),
        Routes.result: (_) => const ResultScreen(),
      },
    );
  }
}

enum GateError {
  noFace,
  multiFace,
  failed,
  faceTooSmall,
  badAngle,
  tightFraming,
}

extension GateErrorMessage on GateError {
  String get message {
    switch (this) {
      case GateError.noFace:
        return 'Yüz tespit edilemedi. Lütfen daha net, önden bir fotoğraf seç.';
      case GateError.multiFace:
        return 'Birden fazla yüz tespit edildi. Lütfen yalnızca tek kişinin olduğu bir fotoğraf seç.';
      case GateError.failed:
        return 'Analiz sırasında bir hata oluştu. Lütfen tekrar dene.';
      case GateError.faceTooSmall:
        return 'Yüz kadrajda çok küçük görünüyor. Lütfen biraz daha yakından çek.';
      case GateError.badAngle:
        return 'Başını dik tutup kameraya düz bakarak tekrar dene.';
      case GateError.tightFraming:
        return 'Kadraj çok dar görünüyor. Lütfen biraz geri çekilip başın tamamı görünecek şekilde çek.';

    }
  }
}


enum FaceRatioClass { short, balanced, long }
enum WidthClass { narrow, medium, wide }

class AnalysisResult {
  // ham metrikler (debug/ilerde)
  final double faceLength;
  final double faceWidth;
  final double foreheadWidth;
  final double ratio;         // length / width
  final double foreheadRatio; // forehead / width

  // UI alanları
  final String faceShapeLabel;
  final String faceShapeReason;

  final String foreheadLabel;
  final String foreheadReason;

  final String jawLabel;
  final String jawReason;

  final String ratioLabel;
  final String ratioReason;

  final List<String> hairGoodBullets;
  final List<String> hairBadBullets;
  final List<String> glassesGoodBullets;
  final List<String> glassesBadBullets;

  const AnalysisResult({
    required this.faceLength,
    required this.faceWidth,
    required this.foreheadWidth,
    required this.ratio,
    required this.foreheadRatio,
    required this.faceShapeLabel,
    required this.faceShapeReason,
    required this.foreheadLabel,
    required this.foreheadReason,
    required this.jawLabel,
    required this.jawReason,
    required this.ratioLabel,
    required this.ratioReason,
    required this.hairGoodBullets,
    required this.hairBadBullets,
    required this.glassesGoodBullets,
    required this.glassesBadBullets,
  });

  static FaceRatioClass _classifyFaceRatio(double r) {
    if (r < 1.10) return FaceRatioClass.short;
    if (r <= 1.40) return FaceRatioClass.balanced; // konservatif
    return FaceRatioClass.long;
  }

  static WidthClass _classifyForehead(double r) {
    if (r < 0.85) return WidthClass.narrow;
    if (r <= 1.00) return WidthClass.medium;
    return WidthClass.wide;
  }

  static String _ratioLabelFromClass(FaceRatioClass c) {
    switch (c) {
      case FaceRatioClass.short:
        return 'Kısa';
      case FaceRatioClass.balanced:
        return 'Dengeli';
      case FaceRatioClass.long:
        return 'Uzun';
    }
  }

  static String _foreheadLabelFromClass(WidthClass c) {
    switch (c) {
      case WidthClass.narrow:
        return 'Dar';
      case WidthClass.medium:
        return 'Orta';
      case WidthClass.wide:
        return 'Geniş';
    }
  }

  static String _decideFaceShape(FaceRatioClass ratioClass) {
    // uzun ve oval karışmasın
    if (ratioClass == FaceRatioClass.long) return 'Uzun (Dikdörtgen)';
    return 'Oval';
  }

  factory AnalysisResult.fromMesh({
    required List<FaceMeshPoint> points,
    required ui.Size imageSize,
    required Offset Function(int idx) pt,  // idx -> Offset(x,y)
    required double Function(Offset a, Offset b) dist,
  }) {
    final brow = pt(MeshIdx.browCenter);
    final chin = pt(MeshIdx.chinBottom);
    final cheekL = pt(MeshIdx.cheekL);
    final cheekR = pt(MeshIdx.cheekR);
    final templeL = pt(MeshIdx.templeL);
    final templeR = pt(MeshIdx.templeR);

    final faceLength = dist(brow, chin);
    final faceWidth = dist(cheekL, cheekR);
    final foreheadWidth = dist(templeL, templeR);

    final ratio = faceWidth <= 0 ? 0.0 : faceLength / faceWidth;
    final foreheadRatio = faceWidth <= 0 ? 0.0 : foreheadWidth / faceWidth;

    final ratioClass = _classifyFaceRatio(ratio);
    final foreheadClass = _classifyForehead(foreheadRatio);

    final faceShape = _decideFaceShape(ratioClass);

    return AnalysisResult(
      faceLength: faceLength,
      faceWidth: faceWidth,
      foreheadWidth: foreheadWidth,
      ratio: ratio,
      foreheadRatio: foreheadRatio,

      faceShapeLabel: faceShape,
      faceShapeReason: 'Uzunluk/Genişlik: ${ratio.toStringAsFixed(2)}',

      foreheadLabel: _foreheadLabelFromClass(foreheadClass),
      foreheadReason: 'Alın/Genişlik: ${foreheadRatio.toStringAsFixed(2)}',

      // sprint 5te çene metriği eklenecek şimdilik sabit
      jawLabel: 'Yumuşak',
      jawReason: 'MVP: çene metriği henüz eklenmedi.',

      ratioLabel: _ratioLabelFromClass(ratioClass),
      ratioReason: 'Oran (L/W): ${ratio.toStringAsFixed(2)}',

      hairGoodBullets: const [
        'Orta uzunluk kesimler — dengeyi korur.',
        'Katlı saç modelleri — yüz hatlarına hareket katar.',
        'Yan ayrım — simetriyi yumuşatır.',
      ],
      hairBadBullets: const [
        'Tepede aşırı hacim — yüzü daha uzun gösterebilir.',
        'Çok uzun ve düz — yüz uzunluğunu vurgulayabilir.',
      ],
      glassesGoodBullets: const [
        'Yuvarlatılmış köşeli çerçeveler — geçişleri yumuşatır.',
        'Orta kalınlıkta çerçeveler — denge sağlar.',
      ],
      glassesBadBullets: const [
        'Çok köşeli/sert çerçeveler — hatları sertleştirebilir.',
      ],
    );
  }
}

class Routes {
  static const onboarding = '/';
  static const photoGuide = '/photo-guide';
  static const photoPick = '/photo-pick';
  static const loading = '/loading';
  static const result = '/result';
}

class MeshIdx {
  static const browCenter = 9;
  static const chinBottom = 175; // MVP: daha stabil
  static const cheekL = 50;
  static const cheekR = 280;
  static const templeL = 139;
  static const templeR = 368;
}

/// basit ortak UI yardımcıları
class Ui {

  static void showSnack(BuildContext context, String text) {
    final messenger = ScaffoldMessenger.of(context);

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      ),
    );
  }


  static const pad = EdgeInsets.all(20);

  static Widget primaryButton({
    required String text,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: FilledButton(
        onPressed: onPressed,
        child: Text(text),
      ),
    );
  }

  static Widget secondaryButton({
    required String text,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton(
        onPressed: onPressed,
        child: Text(text),
      ),
    );
  }

  static Widget sectionTitle(String text) => Text(
        text,
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
      );

  static Widget body(String text, {Key? key}) => Text(
        text,
        key: key,
        style: const TextStyle(fontSize: 15, height: 1.35),
      );

  static Widget bullet(String text) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(fontSize: 16, height: 1.35)),
          Expanded(
              child: Text(text,
                  style: const TextStyle(fontSize: 15, height: 1.35))),
        ],
      );
}

/// 1) Onboarding
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Stil Rehberi')),
      body: Padding(
        padding: Ui.pad,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Ui.sectionTitle('Yüzüne Daha Uygun Stil Seçeneklerini Keşfet'),
            const SizedBox(height: 12),
            Ui.body(
              'Bu uygulama, yüz geometrini analiz ederek saç ve gözlük gibi stil seçimleri için rehberlik sunar.\n'
              'Sonuçlar kesin değildir ve kişisel tercihlerin yerine geçmez.',
            ),
            const SizedBox(height: 16),
            Ui.bullet('Analiz yalnızca yüklediğin fotoğraf üzerinden yapılır.'),
            Ui.bullet('Fotoğraf cihazdan dışarı çıkmaz; analiz cihaz üzerinde yapılır ve sunucuya yüklenmez.'),
            Ui.bullet('Uygulama fotoğrafını kendi içinde saklamaz; sadece seçtiğin dosya üzerinden işlem yapar.'),
            Ui.bullet('18 yaş ve üzeri kullanım içindir.'),
            const Spacer(),
            Ui.primaryButton(
              text: 'Devam Et',
              onPressed: () => Navigator.pushNamed(context, Routes.photoGuide),
            ),
          ],
        ),
      ),
    );
  }
}

/// 2) Fotoğraf Yönergesi
class PhotoGuideScreen extends StatelessWidget {
  const PhotoGuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fotoğraf Yönergesi')),
      body: Padding(
        padding: Ui.pad,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Ui.sectionTitle('Daha Doğru Sonuçlar İçin'),
            const SizedBox(height: 12),
            Ui.body(
                'Analizin sağlıklı olması için lütfen aşağıdaki önerilere dikkat et:'),
            const SizedBox(height: 16),
            Ui.bullet('Ön profilden, kameraya bakarak'),
            Ui.bullet('Nötr yüz ifadesi'),
            Ui.bullet('İyi ve dengeli ışık'),
            Ui.bullet('Gözlük, şapka veya maske olmadan'),
            Ui.bullet('Makyajsız veya hafif bir makyaj'),
            Ui.bullet('Saç mümkünse yüzden uzak'),
            const SizedBox(height: 16),
            Ui.body('Fotoğraf kalitesi, analiz sonucunu doğrudan etkiler.'),
            const Spacer(),
            Ui.primaryButton(
              text: 'Fotoğraf Çek / Yükle',
              onPressed: () => Navigator.pushNamed(context, Routes.photoPick),
            ),
          ],
        ),
      ),
    );
  }
}

/// 3) Fotoğraf Seçimi (Sprint 1: galeriden seçim)
class PhotoPickScreen extends StatefulWidget {
  const PhotoPickScreen({super.key});

  @override
  State<PhotoPickScreen> createState() => _PhotoPickScreenState();
}

class _PhotoPickScreenState extends State<PhotoPickScreen> {
  final ImagePicker _picker = ImagePicker();
  File? _selectedImage;

  Future<void> _showPermissionDialog({
  required String title,
  required String message,
}) async {
  if (!mounted) return;

  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: () async {
            Navigator.pop(ctx);
            await openAppSettings();
          },
          child: const Text('Ayarları Aç'),
        ),
      ],
    ),
  );
}

  Future<void> _takePhoto() async {
  final status = await Permission.camera.request();
  if (!status.isGranted) {
    await _showPermissionDialog(
      title: 'Kamera izni gerekli',
      message: 'Fotoğraf çekebilmek için kamera izni vermen gerekiyor. Ayarlar > İzinler bölümünden izin verebilirsin.',
    );
    return;
  }

    try {
      final XFile? picked = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 2000,
        preferredCameraDevice: CameraDevice.front, // yüz için mantıklı
      );
      if (picked == null) return;
      setState(() => _selectedImage = File(picked.path));
    } catch (e) {
      if (!mounted) return;
      Ui.showSnack(context, 'Kamera açılamadı.');
    }
  }


  Future<void> _pickFromGallery() async {
    final status = await Permission.photos.request();

    if (!status.isGranted) {
      await _showPermissionDialog(
        title: 'Fotoğraf erişimi gerekli',
        message:
            'Galeriden fotoğraf seçebilmek için fotoğraf erişimine izin vermen gerekiyor. Ayarlar > İzinler bölümünden izin verebilirsin.',
      );
      return;
    }

    try {
      final XFile? picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 2000,
      );
  
      if (picked == null) return; // kullanıcı iptal etti

      setState(() => _selectedImage = File(picked.path));
    } catch (_) {
      if (!mounted) return;
      Ui.showSnack(context, 'Fotoğraf seçilemedi. Tekrar dene.');
    }
  }


  Future<void> _continueToAnalysis() async {
  if (_selectedImage == null) return;

  final result = await Navigator.pushNamed(
    context,
    Routes.loading,
    arguments: _selectedImage!.path,
  );

  if (!mounted) return;

  if (result is GateError) {
    Ui.showSnack(context, result.message);
  }
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fotoğraf Seç')),
      body: SafeArea(
        child: Padding(
          padding: Ui.pad,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Ui.sectionTitle('Fotoğraf Seçimi'),
              const SizedBox(height: 12),
              Ui.body(
                'Fotoğraf cihazdan dışarı çıkmaz; analiz için seçtiğin dosya üzerinden işlem yapılır.',
              ),
              const SizedBox(height: 16),
              if (_selectedImage != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    _selectedImage!,
                    height: 220,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 12),
                Ui.body('Seçildi. İstersen farklı bir fotoğraf seçebilirsin.'),
                const SizedBox(height: 16),
              ] else ...[
                Ui.body('Devam etmek için galeriden bir fotoğraf seç.'),
                const SizedBox(height: 16),
              ],
              Ui.secondaryButton(
                text: 'Galeriden Seç',
                onPressed: _pickFromGallery,
              ),

              const SizedBox(height: 12),

              Ui.secondaryButton(
                text: 'Kamera ile Çek',
                onPressed: _takePhoto,
              ),


              const Spacer(),
              Opacity(
                opacity: _selectedImage == null ? 0.6 : 1,
                child: Ui.primaryButton(
                  text: 'Analize Devam',
                  onPressed: _selectedImage == null
                      ? () {
                          Ui.showSnack(context, 'Önce bir fotoğraf seç.');
                        }
                      : _continueToAnalysis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


/// 4) Loading
class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen> {
  late final FaceMeshDetector _meshDetector =
      FaceMeshDetector(option: FaceMeshDetectorOptions.faceMesh);
  List<FaceMeshPoint>? _meshPoints;
  AnalysisResult? _analysisResult;
  ui.Size? _meshImageSize;

  // Seçilen landmark index’leri
  final Set<int> _pickedIdx = <int>{};
  int? _lastPicked;

  // Elle (klavyeden) girilen landmark index’leri -> mavi
  final Set<int> _manualIdx = <int>{
       234, 454, 338, 67, 9, 152, 377, 199,
    // buraya görmek istediğin indexleri yaz
    // örnek:
    // 9, 175, 50, 280, 139, 368,
  };

  double _dist(Offset a, Offset b) {
    final dx = a.dx - b.dx;
    final dy = a.dy - b.dy;
    return math.sqrt(dx * dx + dy * dy);
  }
  
  Offset _pt(List<FaceMeshPoint> pts, int idx) {
    final p = pts[idx];
    return Offset(p.x, p.y);
  }

  FaceRatioClass _classifyFaceRatio(double r) {
  if (r < 1.10) return FaceRatioClass.short;
  if (r <= 1.40) return FaceRatioClass.balanced; // konservatif: long eşiğini 1.40 yaptık
  return FaceRatioClass.long;
}

  WidthClass _classifyForehead(double r) {
    if (r < 0.85) return WidthClass.narrow;
    if (r <= 1.00) return WidthClass.medium;
    return WidthClass.wide;
  }

  String _decideFaceType({
    required FaceRatioClass ratioClass,
    required WidthClass foreheadClass,
    // jaw yok şimdilik
  }) {
    // uzunu al ovale at kalanı
    if (ratioClass == FaceRatioClass.long) return 'Uzun (Dikdörtgen)';
    return 'Oval';
  }

AnalysisResult _analyzeFromMesh(List<FaceMeshPoint> pts, ui.Size imgSize) {
  Offset pt(int idx) {
    final p = pts[idx];
    return Offset(p.x, p.y);
  }

  return AnalysisResult.fromMesh(
    points: pts,
    imageSize: imgSize,
    pt: pt,
    dist: _dist,
  );
}


  void _onMeshTap(Offset tapPos, ui.Size viewSize) {
    if (_meshPoints == null || _meshImageSize == null) return;

    final mapper = _MeshMapper(imageSize: _meshImageSize!, viewSize: viewSize);

    double best = double.infinity;
    int bestIdx = 0;
    
    for (int i = 0; i < _meshPoints!.length; i++) {
      final p = _meshPoints![i];
      final v = mapper.imageToView(Offset(p.x, p.y));
      final dist = (v - tapPos).distance;
      if (dist < best) {
        best = dist;
        bestIdx = i;
      }
    }
  
    final picked = _meshPoints![bestIdx];
    debugPrint('[PICK] idx=$bestIdx dist=${best.toStringAsFixed(2)} '
        'x=${picked.x.toStringAsFixed(1)} y=${picked.y.toStringAsFixed(1)}');
  
    setState(() {
      _lastPicked = bestIdx;
      if (_pickedIdx.contains(bestIdx)) {
        _pickedIdx.remove(bestIdx); // tekrar tıkla = kaldır
      } else {
        _pickedIdx.add(bestIdx);
      }
    });
  }


  Future<ui.Size> _readImageSize(String path) async {
    final bytes = await File(path).readAsBytes();
    final completer = Completer<ui.Image>();
    ui.decodeImageFromList(bytes, (img) => completer.complete(img));
    final img = await completer.future;
    final size = ui.Size(img.width.toDouble(), img.height.toDouble());
    img.dispose();
    return size;
  }

  String? _startedForPath;

  final List<String> _steps = const [
    'Yüz oranları analiz ediliyor...',
    'Yüz geometrisi değerlendiriliyor...',
    'Stil uyumu eşleştiriliyor...',
  ];

  int _index = 0;
  Timer? _stepTimer;
  bool _textVisible = true;

  static const Duration _stepInterval = Duration(milliseconds: 1400);
  static const Duration _fadeDur = Duration(milliseconds: 180);
  static const Duration _minLoading = Duration(milliseconds: 4200);
  static const Duration _maxLoading = Duration(seconds: 6);

  @override
  void initState() {
    super.initState();

    _stepTimer = Timer.periodic(_stepInterval, (_) {
      if (!mounted) return;

      setState(() => _textVisible = false);

      Future.delayed(_fadeDur, () {
        if (!mounted) return;
        setState(() {
          _index = (_index + 1) % _steps.length;
          _textVisible = true;
        });
      });
    });
  }

  @override
  void dispose() {
    _stepTimer?.cancel();
    _meshDetector.close();
    super.dispose();
  }

  Future<GateError?> _runGate(String imagePath) async {
    try {
      final input = InputImage.fromFilePath(imagePath);

      final options = FaceDetectorOptions(
        performanceMode: FaceDetectorMode.accurate,
        enableClassification: false,
        enableLandmarks: false,
        enableTracking: false,
      );
  
      final detector = FaceDetector(options: options);
  
      try {
        final faces = await detector.processImage(input);
  
        if (faces.isEmpty) return GateError.noFace;
        if (faces.length > 1) return GateError.multiFace;
  
        final face = faces.single;
  
        // Görsel boyutu + yüz kutusu
        final imgSize = await _readImageSize(imagePath);
        final imageArea = imgSize.width * imgSize.height;
  
        final box = face.boundingBox;
        final boxArea = box.width * box.height;
  
        final faceAreaRatio = (imageArea <= 0) ? 0.0 : (boxArea / imageArea);
  
        // Açı bilgileri
        final pitch = (face.headEulerAngleX ?? 0.0);
        final yaw = (face.headEulerAngleY ?? 0.0);
        final roll = (face.headEulerAngleZ ?? 0.0);
  
        // Debug log (her şey hazırken yazdır)
        debugPrint(
          '[GATE] faceAreaRatio=${faceAreaRatio.toStringAsFixed(3)} '
          'pitch=${pitch.toStringAsFixed(1)} '
          'yaw=${yaw.toStringAsFixed(1)} roll=${roll.toStringAsFixed(1)} '
          'box=${box.width.toStringAsFixed(0)}x${box.height.toStringAsFixed(0)} '
          'img=${imgSize.width.toStringAsFixed(0)}x${imgSize.height.toStringAsFixed(0)} '
          'top=${box.top.toStringAsFixed(1)}',
        );
  
        // eşikler
        const minFaceAreaRatio = 0.10;
        const maxPitchDeg = 15.0;
        const maxYawDeg = 20.0;
        const maxRollDeg = 15.0;
  
        // 1) Küçük yüz (önce bunu ele)
        if (faceAreaRatio < minFaceAreaRatio) {
          return GateError.faceTooSmall;
        }
  
        // 2) Açı (sonra açı)
        if (pitch.abs() > maxPitchDeg ||
            yaw.abs() > maxYawDeg ||
            roll.abs() > maxRollDeg) {
          return GateError.badAngle;
        }
  
        // 3) Kadraj dar / üstten kesik (en son)
        const topMarginRatio = 0.03; // 3%
        final topTooClose = box.top <= imgSize.height * topMarginRatio;
  
        // İstersen daha güvenli: sadece yüz belli bir büyüklükteyse uyar
        // (uzak fotolarda gereksiz tightFraming riskini azaltır)
        if (topTooClose && faceAreaRatio > 0.14) {
          return GateError.tightFraming;
        }
  
        return null; // OK
      } finally {
        await detector.close();
      }
    } catch (_) {
      return GateError.failed;
    }
  }


Future<void> _runAnalysis(String imagePath) async {
  final sw = Stopwatch()..start();

  GateError? error;
  try {
    error = await _runGate(imagePath).timeout(_maxLoading);
  } on TimeoutException {
    error = GateError.failed;
  } catch (_) {
    error = GateError.failed;
  }

  AnalysisResult? analysisResult;
  try {
    final input = InputImage.fromFilePath(imagePath);
    final meshes = await _meshDetector.processImage(input);
  
    debugPrint('[MESH] faces=${meshes.length}');
    if (meshes.isNotEmpty) {
      final points = meshes.first.points;
      debugPrint('[MESH] points=${points.length}');
  
      final imgSize = await _readImageSize(imagePath);
  
      if (mounted) {
        setState(() {
          _meshPoints = points;
          _meshImageSize = imgSize;
        });
      }
  
      analysisResult = _analyzeFromMesh(points, imgSize);
    }
  } catch (e) {
    debugPrint('[MESH] failed: $e');
  }

  sw.stop();
  final remaining = _minLoading - sw.elapsed;
  if (remaining > Duration.zero) {
    await Future.delayed(remaining);
  }

  if (!mounted) return;

  if (analysisResult == null) {
    Navigator.pop(context, GateError.failed);
    return;
  }
  
  Navigator.pushReplacementNamed(
    context,
    Routes.result,
    arguments: {
      'imagePath': imagePath,
      'result': analysisResult,
    },
  );
}

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    final imagePath = args is String ? args : null;

    if (imagePath == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.pop(context);
      });
      return const Scaffold(body: SizedBox.shrink());
    }

    if (_startedForPath != imagePath) {
      _startedForPath = imagePath;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _runAnalysis(imagePath),
      );
    }

    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        appBar: AppBar(title: const Text('Analiz')),
        body: Padding(
          padding: Ui.pad,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Ui.sectionTitle('Analiz Yapılıyor'),
              const SizedBox(height: 12),
              SizedBox(
                height: 24 * 2,
                width: double.infinity,
                child: AnimatedOpacity(
                  duration: _fadeDur,
                  opacity: _textVisible ? 1 : 0,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Ui.body(_steps[_index]),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AspectRatio(
                  aspectRatio: 3 / 4,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final viewSize = ui.Size(constraints.maxWidth, constraints.maxHeight);
              
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.file(
                            File(imagePath),
                            fit: BoxFit.cover,
                          ),
                          if (_meshPoints != null && _meshImageSize != null)
                            GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onTapDown: (d) => _onMeshTap(d.localPosition, viewSize),
                              child: CustomPaint(
                                painter: _FaceMeshDebugPainter(
                                  points: _meshPoints!,
                                  imageSize: _meshImageSize!,
                                  manualIdx: _manualIdx,
                                  pickedIdx: _pickedIdx,
                                  lastPicked: _lastPicked,
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),

                      
              
              const LinearProgressIndicator(),
              const SizedBox(height: 10),
              Ui.body('Bu işlem birkaç saniye sürebilir.'),
            ],
          ),
        ),
      ),
    );
  }
}


class _FaceMeshDebugPainter extends CustomPainter {
  final List<FaceMeshPoint> points;
  final ui.Size imageSize;
  final Set<int> pickedIdx;
  final Set<int> manualIdx;
  final int? lastPicked;

  _FaceMeshDebugPainter({
    required this.points,
    required this.imageSize,
    required this.pickedIdx,
    required this.manualIdx,
    required this.lastPicked,
  });

  @override
  void paint(Canvas canvas, ui.Size size) {
    final mapper = _MeshMapper(imageSize: imageSize, viewSize: size);

    final green = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.green;

    final red = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.red;

    final blue = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.blue;

    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final v = mapper.imageToView(Offset(p.x, p.y));

      if (v.dx < 0 || v.dy < 0 || v.dx > size.width || v.dy > size.height) {
        continue;
      }


      final isManual = manualIdx.contains(i);
      final isPicked = pickedIdx.contains(i);
      final isLast = (lastPicked == i);

      final paint = isLast
          ? red
          : (isPicked ? red : (isManual ? blue : green));

      final r = isLast ? 5.5 : (isPicked ? 4.0 : (isManual ? 3.6 : 2.2));
      canvas.drawCircle(v, r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _FaceMeshDebugPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.imageSize != imageSize ||
        oldDelegate.lastPicked != lastPicked ||
        oldDelegate.pickedIdx != pickedIdx;
        oldDelegate.manualIdx != manualIdx;
  }
}


class _MeshMapper {
  final ui.Size imageSize;
  final ui.Size viewSize;

  _MeshMapper({required this.imageSize, required this.viewSize});

  Offset imageToView(Offset p) {
    final fitted = applyBoxFit(BoxFit.cover, imageSize, viewSize);
    final src = fitted.source;
    final dst = fitted.destination;

    final scaleX = dst.width / src.width;
    final scaleY = dst.height / src.height;

    final dx = (viewSize.width - dst.width) / 2.0;
    final dy = (viewSize.height - dst.height) / 2.0;

    final srcLeft = (imageSize.width - src.width) / 2.0;
    final srcTop = (imageSize.height - src.height) / 2.0;

    final x = (p.dx - srcLeft) * scaleX + dx;
    final y = (p.dy - srcTop) * scaleY + dy;
    return Offset(x, y);
  }
}



/// 5) Sonuç (sprint 4: gerçek ölçümlerle)
class ResultScreen extends StatelessWidget {
  const ResultScreen({super.key});

  String _ratioLabel(FaceRatioClass c) {
    switch (c) {
      case FaceRatioClass.short:
        return 'Kısa';
      case FaceRatioClass.balanced:
        return 'Dengeli';
      case FaceRatioClass.long:
        return 'Uzun';
    }
  }

  String _foreheadLabel(WidthClass c) {
    switch (c) {
      case WidthClass.narrow:
        return 'Dar';
      case WidthClass.medium:
        return 'Orta';
      case WidthClass.wide:
        return 'Geniş';
    }
  }

@override
Widget build(BuildContext context) {
  final args = ModalRoute.of(context)?.settings.arguments;

  String? imagePath;
  AnalysisResult? result;

  if (args is Map) {
    imagePath = args['imagePath'] as String?;
    result = args['result'] as AnalysisResult?;
  } else if (args is String) {
    imagePath = args;
  }

  return Scaffold(
    appBar: AppBar(title: const Text('Sonuç')),
    body: ListView(
      padding: Ui.pad,
      children: [
        Ui.sectionTitle('Yüz Geometrin'),
        const SizedBox(height: 8),
        Ui.body('Yüklediğin fotoğrafa göre yapılan tahmini analiz'),
        const SizedBox(height: 12),

        // result null olabilir diye korumalı bas:
        if (result != null) ...[
          _infoCard(
            title: 'Yüz şekli: ${result.faceShapeLabel}',
            subtitle: result.faceShapeReason,
          ),
          _infoCard(
            title: 'Alın genişliği: ${result.foreheadLabel}',
            subtitle: result.foreheadReason,
          ),
          _infoCard(
            title: 'Çene hattı: ${result.jawLabel}',
            subtitle: result.jawReason,
          ),
          _infoCard(
            title: 'Yüz oranı: ${result.ratioLabel}',
            subtitle: result.ratioReason,
          ),
        ] else ...[
          _infoCard(
            title: 'Analiz sonucu alınamadı',
            subtitle: 'Lütfen farklı bir fotoğrafla tekrar dene.',
          ),
        ],

        const SizedBox(height: 16),
        Ui.sectionTitle('Saç Stili Önerileri'),
        const SizedBox(height: 8),

        if (result != null) ...[
          _bulletCard(title: 'Daha Uyumlu Olabilecekler', bullets: result.hairGoodBullets),
          _bulletCard(title: 'Daha Az Uyumlu Olabilecekler', bullets: result.hairBadBullets),
        ],

        const SizedBox(height: 16),
        Ui.sectionTitle('Gözlük Çerçevesi Önerileri'),
        const SizedBox(height: 8),

        if (result != null) ...[
          _bulletCard(title: 'Daha Uyumlu Olabilecekler', bullets: result.glassesGoodBullets),
          _bulletCard(title: 'Daha Az Uyumlu Olabilecekler', bullets: result.glassesBadBullets),
        ],

        const SizedBox(height: 16),
        Ui.sectionTitle('Geri Bildirim'),
        const SizedBox(height: 8),

        if (imagePath != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              File(imagePath),
              height: 180,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 12),
        ],

        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(onPressed: () {}, child: const Text('👍 Faydalı')),
            FilledButton(onPressed: () {}, child: const Text('😐 Kararsızım')),
            FilledButton(onPressed: () {}, child: const Text('👎 Geliştirilebilir')),
          ],
        ),
        const SizedBox(height: 18),
        Ui.primaryButton(
          text: 'Yeniden Analiz Et',
          onPressed: () => Navigator.pushNamedAndRemoveUntil(
            context,
            Routes.photoPick,
            (route) => false,
          ),
        ),
      ],
    ),
  );
}

  Widget _infoCard({required String title, required String subtitle}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(subtitle, style: const TextStyle(height: 1.3)),
          ],
        ),
      ),
    );
  }

  Widget _bulletCard({required String title, required List<String> bullets}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            for (final b in bullets)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• '),
                    Expanded(child: Text(b, style: const TextStyle(height: 1.3))),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
