import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:universal_html/html.dart' as html;
import 'package:core/core.dart';
import 'package:dio/dio.dart';

class DownloadManager {
  final DownloadClient _downloadClient;

  DownloadManager(this._downloadClient);

  Future<String> downloadFile(
      String downloadUrl,
      Future<Directory> directoryToSave,
      String filename,
      String basicAuth,
      {CancelToken? cancelToken}
  ) async {
    final streamController = StreamController<String>();

    try {
      await Future.wait([
        _downloadClient.downloadFile(downloadUrl, basicAuth, cancelToken),
        directoryToSave
      ]).then((values) {
        final fileStream = (values[0] as ResponseBody).stream;
        final tempFilePath = '${(values[1] as Directory).absolute.path}/$filename';

        final file = File(tempFilePath);
        file.createSync(recursive: true);
        var randomAccessFile = file.openSync(mode: FileMode.write);
        late StreamSubscription subscription;

        subscription = fileStream
            .takeWhile((_) => cancelToken == null || !cancelToken.isCancelled)
            .listen((data) {
              subscription.pause();
              randomAccessFile.writeFrom(data).then((_randomAccessFile) {
                randomAccessFile = _randomAccessFile;
                subscription.resume();
                if (cancelToken != null && cancelToken.isCancelled) {
                  streamController.sink.addError(CancelDownloadFileException(cancelToken.cancelError?.message));
                }
              }).catchError((error) async {
                await subscription.cancel();
                streamController.sink.addError(CommonDownloadFileException(error.toString()));
                await streamController.close();
              });
        }, onDone: () async {
          await randomAccessFile.close();
          if (cancelToken != null && cancelToken.isCancelled) {
            streamController.sink.addError(CancelDownloadFileException(cancelToken.cancelError?.message));
          } else {
            streamController.sink.add(tempFilePath);
          }
          await streamController.close();
        }, onError: (error) async {
          await randomAccessFile.close();
          await file.delete();
          streamController.sink.addError(CommonDownloadFileException(error.toString()));
          await streamController.close();
        });
      });
    } catch(exception) {
      if (cancelToken != null && cancelToken.isCancelled) {
        streamController.sink.addError(CancelDownloadFileException(cancelToken.cancelError?.message));
        await streamController.close();
        return streamController.stream.first;
      } else {
        throw exception;
      }
    }
    return streamController.stream.first;
  }

  Future<bool> downloadFileForWeb(String downloadUrl, String filename, String basicAuth) async {
    final headerParam = Map<String, String>();
    headerParam[HttpHeaders.authorizationHeader] = basicAuth;
    headerParam[HttpHeaders.acceptHeader] = DioClient.jmapHeader;

    http.Response res = await http.get(Uri.parse(downloadUrl), headers: headerParam);

    if (res.statusCode == 200) {
      final blob = html.Blob([res.bodyBytes]);
      final url = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.document.createElement('a') as html.AnchorElement
        ..href = url
        ..style.display = 'none'
        ..download = filename;
      html.document.body?.children.add(anchor);

      anchor.click();

      html.document.body?.children.remove(anchor);
      html.Url.revokeObjectUrl(url);

      return true;
    }

    return false;
  }
}