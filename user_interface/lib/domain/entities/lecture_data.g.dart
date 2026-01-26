// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'lecture_data.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_LectureCompleteData _$LectureCompleteDataFromJson(Map<String, dynamic> json) =>
    _LectureCompleteData(
      segments: (json['segments'] as List<dynamic>)
          .map((e) => LectureSegment.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$LectureCompleteDataToJson(
  _LectureCompleteData instance,
) => <String, dynamic>{'segments': instance.segments};

_LectureSegment _$LectureSegmentFromJson(Map<String, dynamic> json) =>
    _LectureSegment(
      idx: (json['idx'] as num).toInt(),
      title: json['title'] as String,
      startSid: json['start_sid'] as String,
      endSid: json['end_sid'] as String,
      detailContent: json['detail_content'] as String,
      funFact: json['fun_fact'] as String?,
    );

Map<String, dynamic> _$LectureSegmentToJson(_LectureSegment instance) =>
    <String, dynamic>{
      'idx': instance.idx,
      'title': instance.title,
      'start_sid': instance.startSid,
      'end_sid': instance.endSid,
      'detail_content': instance.detailContent,
      'fun_fact': instance.funFact,
    };

_TranscriptSentence _$TranscriptSentenceFromJson(Map<String, dynamic> json) =>
    _TranscriptSentence(
      sid: json['sid'] as String,
      text: json['text'] as String,
      start: (json['start'] as num).toInt(),
      end: (json['end'] as num).toInt(),
      role: json['role'] as String,
    );

Map<String, dynamic> _$TranscriptSentenceToJson(_TranscriptSentence instance) =>
    <String, dynamic>{
      'sid': instance.sid,
      'text': instance.text,
      'start': instance.start,
      'end': instance.end,
      'role': instance.role,
    };
