import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:rdesk/src/models/wake_pairing.dart';
import 'package:rdesk/src/services/wake_api.dart';
import 'wake_api_test.dart' show RealHttp;
void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  test('扫码和领取使用配置的服务，证明只在请求体，旧服务提示升级',()async{
    final server=await HttpServer.bind(InternetAddress.loopbackIPv4,0);
    final paths=<String>[];final bodies=<Map<String,dynamic>>[];
    final sub=server.listen((r)async{
      paths.add(r.uri.path);expect(r.uri.query,isEmpty);expect(r.headers.value('authorization'),'Bearer account');
      bodies.add(jsonDecode(await utf8.decoder.bind(r).join()) as Map<String,dynamic>);
      if(r.uri.path.endsWith('/resolve')){r.response.write('{"id":"pc","name":"电脑","state":"pending"}');}
      else if(r.uri.path.endsWith('/claim')){r.response.write('{"target_id":"target"}');}
      else {r.response.statusCode=404;}
      await r.response.close();
    });
    try{await HttpOverrides.runWithHttpOverrides(()async{
      final api=WakeApi(baseUri:()async=>Uri.parse('http://127.0.0.1:${server.port}'),accountToken:()async=>'account');
      try{
        final code=WakePairingCode.parse(jsonEncode({'type':'rdesk-wake-pair','version':1,'id':'a'*32,'proof':'b'*64}));
        expect((await api.resolvePairing(code))['name'],'电脑');
        final session=WakePairingSession(id:'a'*32,qrProof:'b'*64,desktopProof:'c'*64,manualCode:'ABCDABCDABCDABCD',expiresAtMs:123);
        expect(await api.claimPairing(session,'d'*64),'target');
        await expectLater(api.createPairing(name:'pc',deviceId:'pc',mac:'02:11:22:33:44:55'),throwsA(isA<WakeApiException>().having((e)=>e.message,'upgrade','服务器需更新扫码配对功能')));
        expect(bodies[0],code.resolveBody);expect(bodies[1]['enrollment_token'],'d'*64);
        expect(paths.every((p)=>!p.contains('bbb')&&!p.contains('ccc')&&!p.contains('ddd')),isTrue);
      }finally{api.close();}
    },RealHttp());}finally{await sub.cancel();await server.close(force:true);}
  });
}
