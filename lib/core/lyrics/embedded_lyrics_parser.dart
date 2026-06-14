import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;

import '../../utils/log.dart';

/// A pure Dart fallback reader for embedded lyrics from local files.
/// Used on non-Android platforms, test environments, or raw paths.
class EmbeddedLyricsParser {
  /// Extracts embedded lyrics from the file at [filePath] based on file type/extension.
  static Future<String?> extractLyrics(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return null;

    final ext = p.extension(filePath).toLowerCase();
    try {
      if (ext == '.mp3') {
        return await _extractLyricsFromMp3(file);
      } else if (ext == '.flac') {
        return await _extractLyricsFromFlac(file);
      } else if (ext == '.m4a' || ext == '.mp4') {
        return await _extractLyricsFromM4a(file);
      }
    } on Exception catch (e, stack) {
      afLog(
        'error',
        'Embedded lyrics extraction failed',
        error: e,
        stackTrace: stack,
      );
    }
    return null;
  }

  static Future<String?> _extractLyricsFromMp3(File file) async {
    RandomAccessFile? raf;
    try {
      raf = await file.open(mode: FileMode.read);

      final header = await raf.read(10);
      if (header.length < 10) return null;
      if (header[0] != 0x49 || header[1] != 0x44 || header[2] != 0x33) {
        // "ID3"
        return null;
      }

      final version = header[3];
      final tagSize =
          ((header[6] & 0x7F) << 21) |
          ((header[7] & 0x7F) << 14) |
          ((header[8] & 0x7F) << 7) |
          (header[9] & 0x7F);

      final maxReadSize = tagSize < 10 * 1024 * 1024
          ? tagSize
          : 10 * 1024 * 1024;
      final buffer = await raf.read(maxReadSize);

      if (buffer.length < 10) return null;

      int i = 0;
      while (i < buffer.length - 10) {
        // Search for "USLT"
        if (buffer[i] == 0x55 &&
            buffer[i + 1] == 0x53 &&
            buffer[i + 2] == 0x4C &&
            buffer[i + 3] == 0x54) {
          final frameSize = version == 4
              ? ((buffer[i + 4] & 0x7F) << 21) |
                    ((buffer[i + 5] & 0x7F) << 14) |
                    ((buffer[i + 6] & 0x7F) << 7) |
                    (buffer[i + 7] & 0x7F)
              : (buffer[i + 4] << 24) |
                    (buffer[i + 5] << 16) |
                    (buffer[i + 6] << 8) |
                    buffer[i + 7];

          if (frameSize > 0 && i + 10 + frameSize <= buffer.length) {
            final lyrics = _parseUsltFrame(buffer, i, frameSize);
            if (lyrics != null) return lyrics;
          }
          i += 10 + frameSize;
        } else {
          i++;
        }
      }
    } finally {
      await raf?.close();
    }
    return null;
  }

  static String? _parseUsltFrame(Uint8List buffer, int startIndex, int size) {
    final bodyStart = startIndex + 10;
    if (size <= 4) return null;

    final encoding = buffer[bodyStart];
    int textStart = bodyStart + 4; // Skip encoding (1) + language (3)

    if (encoding == 0 || encoding == 3) {
      // Latin1 or UTF-8 (null-terminated)
      while (textStart < bodyStart + size && buffer[textStart] != 0) {
        textStart++;
      }
      textStart++; // skip null
    } else {
      // UTF-16 with BOM or without BOM (double null-terminated)
      while (textStart + 1 < bodyStart + size &&
          !(buffer[textStart] == 0 && buffer[textStart + 1] == 0)) {
        textStart += 2;
      }
      textStart += 2; // skip double null
    }

    if (textStart >= bodyStart + size) return null;
    final textLen = (bodyStart + size) - textStart;
    final textBytes = buffer.sublist(textStart, textStart + textLen);

    if (encoding == 0) {
      return latin1.decode(textBytes);
    } else if (encoding == 1 || encoding == 2) {
      try {
        return _decodeUtf16(textBytes);
      } on Exception catch (e, stack) {
        afLog(
          'error',
          'UTF-16 lyrics decode failed, falling back to UTF-8',
          error: e,
          stackTrace: stack,
        );
        return utf8.decode(textBytes, allowMalformed: true);
      }
    } else {
      return utf8.decode(textBytes, allowMalformed: true);
    }
  }

  static String _decodeUtf16(Uint8List bytes) {
    if (bytes.length < 2) return '';

    // Check BOM
    bool isLittleEndian = true;
    int offset = 0;
    if (bytes[0] == 0xFE && bytes[1] == 0xFF) {
      isLittleEndian = false;
      offset = 2;
    } else if (bytes[0] == 0xFF && bytes[1] == 0xFE) {
      isLittleEndian = true;
      offset = 2;
    }

    final codeUnits = <int>[];
    for (int i = offset; i < bytes.length - 1; i += 2) {
      final val = isLittleEndian
          ? (bytes[i + 1] << 8) | bytes[i]
          : (bytes[i] << 8) | bytes[i + 1];
      codeUnits.add(val);
    }
    return String.fromCharCodes(codeUnits);
  }

  static Future<String?> _extractLyricsFromFlac(File file) async {
    RandomAccessFile? raf;
    try {
      raf = await file.open(mode: FileMode.read);

      final header = await raf.read(4);
      if (header.length < 4) return null;
      if (header[0] != 0x66 ||
          header[1] != 0x4C ||
          header[2] != 0x61 ||
          header[3] != 0x43) {
        // "fLaC"
        return null;
      }

      bool isLast = false;
      while (!isLast) {
        final blockHeader = await raf.read(4);
        if (blockHeader.length < 4) break;

        final headerByte = blockHeader[0];
        isLast = (headerByte & 0x80) != 0;
        final blockType = headerByte & 0x7F;

        final length =
            (blockHeader[1] << 16) | (blockHeader[2] << 8) | blockHeader[3];

        if (blockType == 4) {
          // VORBIS_COMMENT
          final buffer = await raf.read(length);
          if (buffer.length == length) {
            return _parseVorbisComment(buffer);
          }
          break;
        } else {
          await raf.setPosition(await raf.position() + length);
        }
      }
    } finally {
      await raf?.close();
    }
    return null;
  }

  static String? _parseVorbisComment(Uint8List buffer) {
    if (buffer.length < 8) return null;
    int offset = 0;

    final vendorLen = _readInt32LE(buffer, offset);
    offset += 4 + vendorLen;
    if (offset + 4 > buffer.length) return null;

    final commentCount = _readInt32LE(buffer, offset);
    offset += 4;

    for (int i = 0; i < commentCount; i++) {
      if (offset + 4 > buffer.length) break;
      final commentLen = _readInt32LE(buffer, offset);
      offset += 4;
      if (offset + commentLen > buffer.length) break;

      final commentStr = utf8.decode(
        buffer.sublist(offset, offset + commentLen),
        allowMalformed: true,
      );
      offset += commentLen;

      final eq = commentStr.indexOf('=');
      if (eq != -1) {
        final key = commentStr.substring(0, eq).toUpperCase();
        if (key == 'LYRICS' || key == 'UNSYNCEDLYRICS') {
          return commentStr.substring(eq + 1);
        }
      }
    }
    return null;
  }

  static int _readInt32LE(Uint8List buffer, int offset) {
    return (buffer[offset]) |
        (buffer[offset + 1] << 8) |
        (buffer[offset + 2] << 16) |
        (buffer[offset + 3] << 24);
  }

  static Future<String?> _extractLyricsFromM4a(File file) async {
    RandomAccessFile? raf;
    try {
      raf = await file.open(mode: FileMode.read);
      return await _scanM4aAtoms(raf, -1);
    } finally {
      await raf?.close();
    }
  }

  static Future<String?> _scanM4aAtoms(
    RandomAccessFile raf,
    int maxBytes,
  ) async {
    final startPosition = await raf.position();
    final fileLength = await raf.length();

    while (maxBytes < 0 || (await raf.position() - startPosition) < maxBytes) {
      final pos = await raf.position();
      if (pos >= fileLength) break;

      final header = await raf.read(8);
      if (header.length < 8) break;

      final size =
          (header[0] << 24) | (header[1] << 16) | (header[2] << 8) | header[3];
      final type = latin1.decode(header.sublist(4, 8));

      if (size < 8) break;
      final payloadSize = size - 8;

      if (type == 'moov' ||
          type == 'udta' ||
          type == 'meta' ||
          type == 'ilst') {
        if (type == 'meta') {
          final dummy = await raf.read(4);
          if (dummy.length < 4) break;
          final lyrics = await _scanM4aAtoms(raf, payloadSize - 4);
          if (lyrics != null) return lyrics;
        } else {
          final lyrics = await _scanM4aAtoms(raf, payloadSize);
          if (lyrics != null) return lyrics;
        }
        await raf.setPosition(pos + size);
      } else if (type == '©lyr') {
        final dataHeader = await raf.read(8);
        if (dataHeader.length < 8) break;

        final dSize =
            (dataHeader[0] << 24) |
            (dataHeader[1] << 16) |
            (dataHeader[2] << 8) |
            dataHeader[3];
        final dType = latin1.decode(dataHeader.sublist(4, 8));

        if (dType == 'data') {
          final dummyFlags = await raf.read(8);
          if (dummyFlags.length < 8) break;

          final textLen = dSize - 16;
          if (textLen > 0) {
            final textBytes = await raf.read(textLen);
            return utf8.decode(textBytes, allowMalformed: true);
          }
        }
        await raf.setPosition(pos + size);
      } else {
        await raf.setPosition(pos + size);
      }
    }
    return null;
  }
}
