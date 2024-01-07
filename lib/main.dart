import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:tflite_v2/tflite_v2.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
  runApp(MyApp());
}

List<CameraDescription>? cameras;

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.dark(),
      home: HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  CameraController? cameraController;
  CameraImage? cameraImage;
  List? recognitionsList;
  DateTime lastFrameTime = DateTime.now();
  Duration frameDelay = const Duration(milliseconds: 200);
  double zoomLevel = 1.0;
  bool isProcessing = false; // Add this boolean flag

  initCamera() {
    cameraController = CameraController(
      cameras![0],
      ResolutionPreset.high,
    );
    cameraController?.initialize().then((value) {
      setState(() {
        cameraController?.startImageStream((CameraImage image) {
          // Throttle the frame processing rate
          if (DateTime.now().difference(lastFrameTime) > frameDelay) {
            lastFrameTime = DateTime.now();
            setState(() {
              cameraImage = image;
              runModel();
              adjustZoomLevel();
            });
          }
        });
      });
    });
  }

  runModel() async {
    if (isProcessing) {
      return;
    }
    // Set the flag to indicate that a detection is in progress
    isProcessing = true;
    recognitionsList = await Tflite.detectObjectOnFrame(
      bytesList: cameraImage!.planes.map((plane) {
        return plane.bytes;
      }).toList(),
      imageHeight: cameraImage!.height,
      imageWidth: cameraImage!.width,
      imageMean: 127.5,
      imageStd: 127.5,
      numResultsPerClass: 1,
      threshold: 0.4,
    );

    if (recognitionsList != null && recognitionsList!.isNotEmpty) {
      // Sort the list based on confidence in descending order
      recognitionsList!.sort((a, b) => (b['confidenceInClass'] as double)
          .compareTo(a['confidenceInClass'] as double));

      // Keep only the object with the highest confidence
      recognitionsList = [recognitionsList![0]];
      // Rect rect = recognitionsList[["rect"]];
      setState(() {
        cameraImage;
      });
    }
    // Reset the flag after processing is complete
    isProcessing = false;
  }

  adjustZoomLevel() {
    // Check if already processing a detection
    if (isProcessing) {
      return;
    }
// Set the flag to indicate that a detection is in progress
    isProcessing = true;
    if (recognitionsList != null && recognitionsList!.isNotEmpty) {
      double newZoomLevel = calculateZoomLevel(recognitionsList!);

      if (newZoomLevel != zoomLevel) {
        zoomLevel = newZoomLevel;
        cameraController?.setZoomLevel(zoomLevel);
      }
    }
    // Reset the flag after adjusting the zoom level
    isProcessing = false;
  }
  // }

  double calculateZoomLevel(List recognitionsList) {
    if (recognitionsList.isEmpty) {
      return zoomLevel;
    }

    double scaleFactor = 0.0001;
    double averageSize =
        recognitionsList[0]["rect"]["w"] * recognitionsList[0]["rect"]["h"];
    double newZoomLevel = zoomLevel + scaleFactor * averageSize;

    // Ensure that the new zoom level is within acceptable bounds
    newZoomLevel = newZoomLevel.clamp(1.0, 5.0);

    return newZoomLevel;
  }

  Future loadModel() async {
    Tflite.close();
    await Tflite.loadModel(
      model: "assets/ssd_mobilenet.tflite",
      labels: "assets/ssd_mobilenet.txt",
    );
  }

  @override
  void initState() {
    super.initState();
    loadModel();
    initCamera();
  }

  @override
  void dispose() {
    cameraController?.stopImageStream();
    cameraController?.dispose();
    Tflite.close();
    super.dispose();
  }

  List<Widget> displayBoxesAroundRecognizedObjects(Size screen) {
    if (recognitionsList == null) return [];

    double factorX = screen.width;
    double factorY = screen.height;

    Color colorPick = Colors.pink;

    return recognitionsList!.map((result) {
      return Positioned(
        left: result["rect"]["x"] * factorX,
        top: result["rect"]["y"] * factorY,
        width: result["rect"]["w"] * factorX,
        height: result["rect"]["h"] * factorY,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(Radius.circular(10.0)),
            border: Border.all(color: Colors.pink, width: 2.0),
          ),
          child: Text(
            "${result['detectedClass']} ${(result['confidenceInClass'] * 100).toStringAsFixed(0)}%",
            style: TextStyle(
              background: Paint()..color = colorPick,
              color: Colors.black,
              fontSize: 18.0,
            ),
          ),
        ),
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    Size size = MediaQuery.of(context).size;
    List<Widget> list = [];

    list.add(
      Positioned(
        top: 0.0,
        left: 0.0,
        width: size.width,
        height: size.height - 100,
        child: SizedBox(
          height: size.height - 100,
          child: (!cameraController!.value.isInitialized)
              ? Container()
              : AspectRatio(
                  aspectRatio: cameraController!.value.aspectRatio,
                  child: CameraPreview(cameraController!),
                ),
        ),
      ),
    );

    if (cameraImage != null) {
      list.addAll(displayBoxesAroundRecognizedObjects(size));
    }

    return SafeArea(
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Container(
          margin: const EdgeInsets.only(top: 50),
          color: Colors.black,
          child: Stack(
            children: list,
          ),
        ),
      ),
    );
  }
}
