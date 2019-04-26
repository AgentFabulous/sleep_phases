import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

void main() => runApp(new MyApp());

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => new _MyAppState();
}

class _MyAppState extends State<MyApp> {
  FlutterBluetoothSerial bluetooth = FlutterBluetoothSerial.instance;

  List<BluetoothDevice> _devices = [];
  BluetoothDevice _device;
  bool _connected = false;
  bool _pressed = false;
  String buffer = "";
  String bufferedPacket = "";
  DateTime motionTestTime;
  bool motionCheck;

  @override
  void initState() {
    super.initState();
    initPlatformState();
  }

  Future<void> initPlatformState() async {
    List<BluetoothDevice> devices = [];

    try {
      devices = await bluetooth.getBondedDevices();
    } on PlatformException {}

    bluetooth.onStateChanged().listen((state) {
      switch (state) {
        case FlutterBluetoothSerial.CONNECTED:
          setState(() {
            _connected = true;
            _pressed = false;
          });
          break;
        case FlutterBluetoothSerial.DISCONNECTED:
          setState(() {
            _connected = false;
            _pressed = false;
          });
          break;
        default:
          // TODO
          print(state);
          break;
      }
    });

    bluetooth.onRead().listen((msg) {
      if (!msg.contains("\n"))
        buffer += msg;
      else {
        List<String> bufSplit = msg.split("\n");
        buffer += bufSplit[0];
        setState(() {
          bufferedPacket = buffer;
          print(bufferedPacket);
        });
        buffer = bufSplit[1];
      }
    });

    if (!mounted) return;
    setState(() {
      _devices = devices;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: Text('Flutter Bluetooth Serial'),
        ),
        body: Container(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(10.0, 10.0, 10.0, 0.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Text(
                      'Device:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    DropdownButton(
                      items: _getDeviceItems(),
                      onChanged: (value) => setState(() => _device = value),
                      value: _device,
                    ),
                    RaisedButton(
                      onPressed:
                          _pressed ? null : _connected ? _disconnect : _connect,
                      child: Text(_connected ? 'Disconnect' : 'Connect'),
                    ),
                  ],
                ),
              ),
              Builder(builder: (context) {
                String statusString;
                switch (getStatus()) {
                  case 1:
                    statusString = "Light sleep";
                    break;
                  case 2:
                    statusString = "Deep sleep";
                    break;
                  default:
                    statusString = "Awake";
                    break;
                }
                return Text(statusString, style: TextStyle(fontSize: 40.0));
              }),
              Padding(
                padding: EdgeInsets.all(30.0),
                child: parsePacket(bufferedPacket).length < 3
                    ? CircularProgressIndicator()
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Padding(
                              padding: const EdgeInsets.only(
                                  left: 10.0, right: 10.0),
                              child: Text("Luminiscence: " +
                                  parsePacket(bufferedPacket)[0])),
                          Padding(
                              padding: const EdgeInsets.only(
                                  left: 10.0, right: 10.0),
                              child: Text("Temperature: " +
                                  parsePacket(bufferedPacket)[2] +
                                  "°C")),
                          Padding(
                              padding: const EdgeInsets.only(
                                  left: 10.0, right: 10.0),
                              child: Text("Humidity: " +
                                  parsePacket(bufferedPacket)[1] +
                                  "%")),
                          Padding(
                              padding: const EdgeInsets.only(
                                  left: 10.0, right: 10.0),
                              child: Text("Motion: " +
                                  (parsePacket(bufferedPacket)[4] != null
                                          ? (int.parse(parsePacket(
                                                  bufferedPacket)[4]) ==
                                              1)
                                          : false.toString())
                                      .toString())),
                        ],
                      ),
              )
            ],
          ),
        ),
      ),
    );
  }

  List<DropdownMenuItem<BluetoothDevice>> _getDeviceItems() {
    List<DropdownMenuItem<BluetoothDevice>> items = [];
    if (_devices.isEmpty) {
      items.add(DropdownMenuItem(
        child: Text('NONE'),
      ));
    } else {
      _devices.forEach((device) {
        items.add(DropdownMenuItem(
          child: Text(device.name),
          value: device,
        ));
      });
    }
    return items;
  }

  int getStatus() {
    DateTime currentTS = DateTime.now();
    if (parsePacket(bufferedPacket).length < 4) {
      return 0;
    }
    if (motionTestTime == null ||
        motionTestTime.difference(currentTS).inMinutes >= 10 ||
        !motionCheck) {
      motionCheck = (parsePacket(bufferedPacket)[4] != null
          ? (int.parse(parsePacket(bufferedPacket)[4]) == 1)
          : false.toString());
      motionTestTime = currentTS;
    }
    if (int.parse(parsePacket(bufferedPacket)[0]) <= 150 &&
        (currentTS.hour >= 22 && currentTS.hour <= 6)) {
      if (motionCheck)
        return 1;
      else
        return 2;
    } else
      return 0;
  }

  void _connect() {
    if (_device == null) {
      show('No device selected.');
    } else {
      bluetooth.isConnected.then((isConnected) {
        if (!isConnected) {
          bluetooth.connect(_device).catchError((error) {
            setState(() => _pressed = false);
          });
          setState(() => _pressed = true);
        }
      });
    }
  }

  void _disconnect() {
    bluetooth.disconnect();
    setState(() => _pressed = true);
  }

  ///
  ///
  ///
  Future show(
    String message, {
    Duration duration: const Duration(seconds: 3),
  }) async {
    await new Future.delayed(new Duration(milliseconds: 100));
    Scaffold.of(context).showSnackBar(
      new SnackBar(
        content: new Text(
          message,
          style: new TextStyle(
            color: Colors.white,
          ),
        ),
        duration: duration,
      ),
    );
  }
}

List parsePacket(String packet) {
  List<String> data = packet.split(";");
  List<String> ret = new List();
  data.forEach((String f) {
    if (f.split(":").length > 1) ret.add(f.split(":")[1]);
  });
  return ret;
}
