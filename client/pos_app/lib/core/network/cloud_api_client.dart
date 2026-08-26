import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:pos_app/core/config/app_environment.dart';
import 'package:pos_app/core/storage/secure_token_store.dart';

final class CloudApiClient {
  CloudApiClient({http.Client? client,SecureTokenStore? tokens}):_client=client??http.Client(),_tokens=tokens??const SecureTokenStore();
  final http.Client _client; final SecureTokenStore _tokens;
  Uri _uri(String path,[Map<String,String>? q])=>Uri.parse('${AppEnvironment.apiBaseUrl}$path').replace(queryParameters:q);
  Future<Map<String,Object?>> post(String path,Map<String,Object?> body,{bool authenticated=true}) async {
    final headers={'content-type':'application/json'}; if(authenticated){final t=await _tokens.accessToken();if(t!=null)headers['authorization']='Bearer $t';}
    final r=await _client.post(_uri(path),headers:headers,body:jsonEncode(body)); return _decode(r);
  }
  Future<Map<String,Object?>> get(String path,{Map<String,String>? query}) async {final headers=<String,String>{};final t=await _tokens.accessToken();if(t!=null)headers['authorization']='Bearer $t';final r=await _client.get(_uri(path,query),headers:headers);return _decode(r);}
  Map<String,Object?> _decode(http.Response r){if(r.statusCode<200||r.statusCode>=300)throw StateError('La nube respondió ${r.statusCode}.');final x=jsonDecode(r.body);return x is Map?Map<String,Object?>.from(x):{'items':x};}
}
