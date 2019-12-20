import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:intl/date_symbol_data_local.dart';
import 'dart:async';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:rflutter_alert/rflutter_alert.dart';
import 'dart:convert';

void main() {
  //materialApp is e.g. useful for AlertDialog and so on...
  runApp(new MaterialApp(home: new MyApp()));
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => new _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _isRecording = false;
  String _path;

  StreamSubscription _recorderSubscription;
  StreamSubscription _dbPeakSubscription;
  StreamSubscription _playerSubscription;
  FlutterSound flutterSound;

  String _recorderTxt = '00:00:00';
  String _playerTxt = '00:00:00';
  double _dbLevel = 0.0;
  double _maxDbLevel = 0.0;
  double gotUpdateDB = 0.0;
  int sendedRequests = 0;
  int errorFromSendedRequests = 0;

  DateTime startDate;
  DateTime endDate;
  DateTime dateNow = new DateTime.now();

  double sliderCurrentPosition = 0.0;
  double maxDuration = 1.0;
  double sumDB = 0.0;

  final myIpController = TextEditingController();
  final myPortController = TextEditingController();

  Geolocator _geolocator;
  Position _position;
  Timer timer;

  var recSoundValues = new List();

  void checkPermission() {
    _geolocator.checkGeolocationPermissionStatus().then((status) { print('status: $status'); });
    _geolocator.checkGeolocationPermissionStatus(locationPermission: GeolocationPermission.locationAlways).then((status) { print('always status: $status'); });
    _geolocator.checkGeolocationPermissionStatus(locationPermission: GeolocationPermission.locationWhenInUse)..then((status) { print('whenInUse status: $status'); });
  }

  @override
  void initState() {
    super.initState();
    //check permission for GPS
    _geolocator = Geolocator();
    LocationOptions locationOptions = LocationOptions(accuracy: LocationAccuracy.high, distanceFilter: 1);
    checkPermission();
   // print(_geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high, locationPermissionLevel: GeolocationPermission.locationAlways));
     StreamSubscription positionStream = _geolocator.getPositionStream(locationOptions).listen(
              (Position position) {
            _position = position;
          });

    /*StreamSubscription<Position> positionStream = _geolocator.getPositionStream(locationOptions).listen(
    (Position position) {
        print(position == null ? 'Unknown' : position.latitude.toString() + ', ' + position.longitude.toString());
    });*/

    //init audio
    flutterSound = new FlutterSound();
    flutterSound.setSubscriptionDuration(0.01);
    flutterSound.setDbPeakLevelUpdate(0.8);
    flutterSound.setDbLevelEnabled(true);
    initializeDateFormatting();
  }

  //for timer .. ? is the null navigation operator which checks if timer was init
  @override
  void dispose() {
    timer?.cancel();
    myIpController.dispose();
    myPortController.dispose();
    super.dispose();
  }

  void startRecorder() async{
    try {
      this._maxDbLevel = 0;
      startDate = new DateTime.now();
      endDate = null;
      //_geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high, locationPermissionLevel: GeolocationPermission.location);
      
      String path = await flutterSound.startRecorder(Platform.isIOS ? 'ios.m4a' : 'android.mp4');
      print('startRecorder: $path');

      _recorderSubscription = flutterSound.onRecorderStateChanged.listen((e) {
        DateTime date = new DateTime.fromMillisecondsSinceEpoch(
            e.currentPosition.toInt(),
            isUtc: true);
        String txt = DateFormat('mm:ss:SS', 'en_GB').format(date);

        this.setState(() {
          this._recorderTxt = txt.substring(0, 8);
        });
      });

      _dbPeakSubscription =
          flutterSound.onRecorderDbPeakChanged.listen((value) {
            // print("got update -> $value");
            
            //check if rec List if empty else make a new startDate
            if(recSoundValues.isEmpty){
              startDate = new DateTime.now();
            }

            gotUpdateDB = double.parse("$value");
            //Add value to rec List
            recSoundValues.add(gotUpdateDB);

            setState(() {
              this._dbLevel = value;
            });
          });

      this.setState(() {
        this._isRecording = true;
        this._path = path;
      });
    } catch (err) {
      print('startRecorder error: $err');
    }
  }

  void stopRecorder() async{
    try {
      endDate = new DateTime.now();
      String result = await flutterSound.stopRecorder();
      print('stopRecorder: $result');

      if (_recorderSubscription != null) {
        _recorderSubscription.cancel();
        _recorderSubscription = null;
      }
      if (_dbPeakSubscription != null) {
        _dbPeakSubscription.cancel();
        _dbPeakSubscription = null;
      }

      this.setState(() {
        this._isRecording = false;
      });
    } catch (err) {
      print('stopRecorder error: $err');
    }
  }

  void startPlayer() async{
    try {
      String path = await flutterSound.startPlayer(this._path);
      await flutterSound.setVolume(1.0);
      print('startPlayer: $path');

      _playerSubscription = flutterSound.onPlayerStateChanged.listen((e) {
        if (e != null) {
          sliderCurrentPosition = e.currentPosition;
          maxDuration = e.duration;

          DateTime date = new DateTime.fromMillisecondsSinceEpoch(
              e.currentPosition.toInt(),
              isUtc: true);
          String txt = DateFormat('mm:ss:SS', 'en_GB').format(date);
          this.setState(() {
            //this._isPlaying = true;
            this._playerTxt = txt.substring(0, 8);
          });
        }
      });
      
    } catch (err) {
      print('error: $err');
    }
  }

  void stopPlayer() async{
    try {
      String result = await flutterSound.stopPlayer();
      print('stopPlayer: $result');
      if (_playerSubscription != null) {
        _playerSubscription.cancel();
        _playerSubscription = null;
      }

      this.setState(() {
        //this._isPlaying = false;
      });
    } catch (err) {
      print('error: $err');
    }
  }

  void pausePlayer() async{
    String result = await flutterSound.pausePlayer();
    print('pausePlayer: $result');
  }

  void resumePlayer() async{
    String result = await flutterSound.resumePlayer();
    print('resumePlayer: $result');
  }

  void seekToPlayer(int milliSecs) async{
    String result = await flutterSound.seekToPlayer(milliSecs);
    print('seekToPlayer: $result');
  }

  String getDate(){
    var newDate = new DateTime.now();
    return newDate.toString();
  }

  double getMaxNoise() {
    double db = this._dbLevel;
    double maxdb = this._maxDbLevel;
    if(maxdb < db){
      this._maxDbLevel = this._dbLevel;
      return this._maxDbLevel;
    }else {
      return this._maxDbLevel;
    }
  }

  //function to calc avg db value from rec List and make post request
  void storeValues(){
        endDate = new DateTime.now();
        print("Text sound : " + this._recorderTxt);
        
        var length = recSoundValues.length;
        
        //sum up value from rec List 
        for (final x in recSoundValues) {
          sumDB = sumDB + x;
        }

        //calc avg from sumDB
        double avg = sumDB/length;
        print("Avg: " + avg.toString());

        //clear rec List and set sumDB to 0 for next run
        sumDB = 0;
        recSoundValues.clear();

        //send data
        sendData(avg);
  }

  Future sendData(double avg) async {
      //get ip and port from Textfield
      var ipAdressToConnect = myIpController.text;
      var portNrToConnect = myPortController.text;

      try {
        var lat = '${_position != null ? _position.latitude.toString() : '0'}';
        var lng = '${_position != null ? _position.longitude.toString() : '0'}';
        var start = json.encode(startDate.toIso8601String());
        var end = json.encode(endDate.toIso8601String());
        var jsonStr = '{"dbLevel": "'+avg.toString()+'", "startDate": '+start+', "endDate": '+end+', "lat": "'+lat+'", "lng": "'+lng+'"}';
        
        //for test with emulator localhost = 10.0.2.2
        var url = 'http://'+ipAdressToConnect+':'+portNrToConnect+'';  
        var response = await http.post(url, headers: {"Content-Type": "application/json"}, body: jsonStr).timeout(Duration(seconds: 5));
      
        if(response.statusCode == 200){
          sendedRequests++;
          //Alert(context: context, title: "Data sended", desc: "Code: " + response.statusCode.toString()).show();
        } else {
          errorFromSendedRequests++;
          Alert(context: context, title: "eRROR WHILE SENDING", desc: "Code: "+ response.statusCode.toString()).show();
        }

        print('Response status: ${response.statusCode}');
        print('Response body: ${response.body}');
      } catch (e) {
        errorFromSendedRequests++;
        Alert(context: context, title: "Connection ERROR", desc: "Socket or Time execption").show();
        print("Error: " + e.toString());
        return throw Exception('Connection Error');
      }
  }


  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Flutter Sound'),
        ),
        body: ListView(
          children: <Widget>[
            Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Container(
                    padding: const EdgeInsets.all(0.0),
                    child: new Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    new TextFormField(
                        decoration: new InputDecoration(labelText: "Enter IP"),
                        keyboardType: TextInputType.number,
                        controller: myIpController,//..text = '10.0.2.2',
                    ),
                    new TextFormField(
                        decoration: new InputDecoration(labelText: "Enter Port nr"),
                        keyboardType: TextInputType.number,
                        controller: myPortController..text = '8071',
                    ),
                    new Text(
                        "Sended requests: "+sendedRequests.toString(),
                    ),
                    new Text(
                        "Errors requests: "+errorFromSendedRequests.toString(),
                    ),
                  ],
                )),
                Container(
                  margin: EdgeInsets.only(top: 24.0, bottom:16.0),
                  
                  child: Text(
                    this._recorderTxt,
                    style: TextStyle(
                      fontSize: 48.0,
                      color: Colors.black,
                    ) ,
                  ) , 
                ),
                Container(
                  margin: EdgeInsets.only(top: 24.0, bottom:16.0),
                  
                  child: Text(
                    "Current DB: " +this._dbLevel.toStringAsFixed(2),
                    style: TextStyle(
                      fontSize: 18.0,
                      color: Colors.black,
                    ) ,
                  ) , 
                )/*,
                _isRecording ? LinearProgressIndicator(
                  value: 100.0 / 160.0 * (this._dbLevel ?? 1) / 100,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
                  backgroundColor: Colors.red,
                ) : Container()*/
              ],
            ),
            Row(
              children: <Widget>[
                Container(
                  width: 56.0,
                  height: 56.0,
                  child: ClipOval(
                    child: MaterialButton(
                      onPressed: () {
                        if (!this._isRecording) {
                          //start timer for doing job and  reset info num requests
                          timer = Timer.periodic(Duration(seconds: 10), (Timer t) => storeValues());
                          errorFromSendedRequests = 0;
                          sendedRequests = 0;
                          return this.startRecorder();
                        }

                        //stop rec if running and cancle timer()
                        this.stopRecorder();
                        timer.cancel();
                        
                      },
                      padding: EdgeInsets.all(8.0),
                      child: Image(
                        image: this._isRecording ? AssetImage('res/icons/ic_stop.png') : AssetImage('res/icons/ic_mic.png'),
                      ),
                    ),
                  ),
                ),
              ],
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
            ),
            Row(
              children: <Widget>[
            Container(
              margin: EdgeInsets.only(top: 24.0, bottom:16.0),
                  width: 200.0,
                  height: 56.0,
                  
                  child:  Text(
                    "Max DB: " + getMaxNoise().toStringAsFixed(2),
                    
                    //this._dbLevel.toString(),
                    style: TextStyle(
                      fontSize: 28.0,
                      color: Colors.black,
                    ) ,
                  ) ,
                ),
              ],
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
            ),
            Row(
              children: <Widget>[
                Container(
                  margin: EdgeInsets.only(top: 24.0, bottom:1.0),
                  width: 290.0,
                  height: 36.0,
                  child:  Text(
                    //getDate().toString(),
                    "Start: " + startDate.toString(),
                    style: TextStyle(
                      fontSize: 18.0,
                      color: Colors.black,
                    ) ,
                  ) ,
                ),
              ],
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
            ),
            Row(
              children: <Widget>[
                Container(
                 // margin: EdgeInsets.only(top: 24.0, bottom:16.0),
                  width: 290.0,
                  height: 36.0,
                  child:  Text(
                    //getDate().toString(),
                    "End:   " +endDate.toString(),
                    style: TextStyle(
                      fontSize: 18.0,
                      color: Colors.black,
                    ) ,
                  ) ,
                ),
              ],
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
            ),
            Row(
              children: <Widget>[
                Container(
                 // margin: EdgeInsets.only(top: 24.0, bottom:16.0),
                  width: 290.0,
                  height: 36.0,
                  child: Text(
                    'Latitude: ${_position != null ? _position.latitude.toString() : '0'},'
                    ' Longitude: ${_position != null ? _position.longitude.toString() : '0'}'
                  ) ,
                ),
              ],
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
            ),
          ],
        ),
      ),
    );
  }
}
