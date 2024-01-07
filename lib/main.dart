import 'dart:async';

import 'package:tflite_v2/tflite_v2.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

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
  Duration minFrameInterval = const Duration(milliseconds: 200);
  double zoomLevel = 1.0;

  // Timer? debounceTimer;
  // Duration debounceDuration = const Duration(milliseconds: 500);

  initCamera() {
    cameraController = CameraController(cameras![0], ResolutionPreset.high);
    cameraController?.initialize().then((value) {
      setState(() {
        cameraController?.startImageStream((image) {
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
    // Cancel any existing debounce timer
    // debounceTimer?.cancel();

    // DateTime currentTime = DateTime.now();
    // if (currentTime.difference(lastFrameTime) < minFrameInterval) {
    //   // Skip processing this frame if it's too soon
    //   return;
    // }

// Set a new debounce timer
    // debounceTimer = Timer(debounceDuration, () async {
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

      setState(() {
        cameraImage;
      });
    }
    // });
    // lastFrameTime = currentTime;
  }

  adjustZoomLevel() {
    if (recognitionsList != null && recognitionsList!.isNotEmpty) {
      // Calculate zoom level based on detected objects
      // You can customize this logic based on your requirements
      double newZoomLevel = calculateZoomLevel(recognitionsList!);

      if (newZoomLevel != zoomLevel) {
        zoomLevel = newZoomLevel;
        cameraController?.setZoomLevel(zoomLevel);
      }
    }
  }

  double calculateZoomLevel(List recognitionsList) {
    if (recognitionsList.isEmpty) {
      // No detected objects, maintain the current zoom level
      return zoomLevel;
    }

    // Calculate the average size of detected objects
    double totalSize = 0.0;
    for (var result in recognitionsList) {
      double width = result['rect']['w'];
      double height = result['rect']['h'];
      totalSize += width * height;
    }

    // Calculate the average size
    double averageSize = totalSize / recognitionsList.length;

    // You can customize this scaling factor based on your requirements
    double scaleFactor = 0.0001;

    // Adjust the zoom level based on the average size
    double newZoomLevel = zoomLevel + scaleFactor * averageSize;

    // Ensure that the new zoom level is within acceptable bounds
    newZoomLevel = newZoomLevel.clamp(1.0, 5.0);

    // Debugging prints
    print('Average Size: $averageSize');
    print('New Zoom Level: $newZoomLevel');

    return newZoomLevel;
  }

  Future loadModel() async {
    Tflite.close();
    await Tflite.loadModel(
        model: "assets/ssd_mobilenet.tflite",
        labels: "assets/ssd_mobilenet.txt");
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
