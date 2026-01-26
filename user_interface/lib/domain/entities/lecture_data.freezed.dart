// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'lecture_data.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$LectureCompleteData {

// "segments" 配列の中身
 List<LectureSegment> get segments;
/// Create a copy of LectureCompleteData
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LectureCompleteDataCopyWith<LectureCompleteData> get copyWith => _$LectureCompleteDataCopyWithImpl<LectureCompleteData>(this as LectureCompleteData, _$identity);

  /// Serializes this LectureCompleteData to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LectureCompleteData&&const DeepCollectionEquality().equals(other.segments, segments));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(segments));

@override
String toString() {
  return 'LectureCompleteData(segments: $segments)';
}


}

/// @nodoc
abstract mixin class $LectureCompleteDataCopyWith<$Res>  {
  factory $LectureCompleteDataCopyWith(LectureCompleteData value, $Res Function(LectureCompleteData) _then) = _$LectureCompleteDataCopyWithImpl;
@useResult
$Res call({
 List<LectureSegment> segments
});




}
/// @nodoc
class _$LectureCompleteDataCopyWithImpl<$Res>
    implements $LectureCompleteDataCopyWith<$Res> {
  _$LectureCompleteDataCopyWithImpl(this._self, this._then);

  final LectureCompleteData _self;
  final $Res Function(LectureCompleteData) _then;

/// Create a copy of LectureCompleteData
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? segments = null,}) {
  return _then(_self.copyWith(
segments: null == segments ? _self.segments : segments // ignore: cast_nullable_to_non_nullable
as List<LectureSegment>,
  ));
}

}


/// Adds pattern-matching-related methods to [LectureCompleteData].
extension LectureCompleteDataPatterns on LectureCompleteData {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _LectureCompleteData value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _LectureCompleteData() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _LectureCompleteData value)  $default,){
final _that = this;
switch (_that) {
case _LectureCompleteData():
return $default(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _LectureCompleteData value)?  $default,){
final _that = this;
switch (_that) {
case _LectureCompleteData() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<LectureSegment> segments)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _LectureCompleteData() when $default != null:
return $default(_that.segments);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<LectureSegment> segments)  $default,) {final _that = this;
switch (_that) {
case _LectureCompleteData():
return $default(_that.segments);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<LectureSegment> segments)?  $default,) {final _that = this;
switch (_that) {
case _LectureCompleteData() when $default != null:
return $default(_that.segments);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _LectureCompleteData implements LectureCompleteData {
  const _LectureCompleteData({required final  List<LectureSegment> segments}): _segments = segments;
  factory _LectureCompleteData.fromJson(Map<String, dynamic> json) => _$LectureCompleteDataFromJson(json);

// "segments" 配列の中身
 final  List<LectureSegment> _segments;
// "segments" 配列の中身
@override List<LectureSegment> get segments {
  if (_segments is EqualUnmodifiableListView) return _segments;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_segments);
}


/// Create a copy of LectureCompleteData
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LectureCompleteDataCopyWith<_LectureCompleteData> get copyWith => __$LectureCompleteDataCopyWithImpl<_LectureCompleteData>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$LectureCompleteDataToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _LectureCompleteData&&const DeepCollectionEquality().equals(other._segments, _segments));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_segments));

@override
String toString() {
  return 'LectureCompleteData(segments: $segments)';
}


}

/// @nodoc
abstract mixin class _$LectureCompleteDataCopyWith<$Res> implements $LectureCompleteDataCopyWith<$Res> {
  factory _$LectureCompleteDataCopyWith(_LectureCompleteData value, $Res Function(_LectureCompleteData) _then) = __$LectureCompleteDataCopyWithImpl;
@override @useResult
$Res call({
 List<LectureSegment> segments
});




}
/// @nodoc
class __$LectureCompleteDataCopyWithImpl<$Res>
    implements _$LectureCompleteDataCopyWith<$Res> {
  __$LectureCompleteDataCopyWithImpl(this._self, this._then);

  final _LectureCompleteData _self;
  final $Res Function(_LectureCompleteData) _then;

/// Create a copy of LectureCompleteData
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? segments = null,}) {
  return _then(_LectureCompleteData(
segments: null == segments ? _self._segments : segments // ignore: cast_nullable_to_non_nullable
as List<LectureSegment>,
  ));
}


}


/// @nodoc
mixin _$LectureSegment {

 int get idx; String get title;// JSONのキー名がCamelCaseじゃない場合、@JsonKeyで指定します
@JsonKey(name: 'start_sid') String get startSid;@JsonKey(name: 'end_sid') String get endSid;// Markdownの本文
@JsonKey(name: 'detail_content') String get detailContent;// 豆知識（無い場合も考慮して nullable にしておくと安全です）
@JsonKey(name: 'fun_fact') String? get funFact;
/// Create a copy of LectureSegment
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LectureSegmentCopyWith<LectureSegment> get copyWith => _$LectureSegmentCopyWithImpl<LectureSegment>(this as LectureSegment, _$identity);

  /// Serializes this LectureSegment to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LectureSegment&&(identical(other.idx, idx) || other.idx == idx)&&(identical(other.title, title) || other.title == title)&&(identical(other.startSid, startSid) || other.startSid == startSid)&&(identical(other.endSid, endSid) || other.endSid == endSid)&&(identical(other.detailContent, detailContent) || other.detailContent == detailContent)&&(identical(other.funFact, funFact) || other.funFact == funFact));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,idx,title,startSid,endSid,detailContent,funFact);

@override
String toString() {
  return 'LectureSegment(idx: $idx, title: $title, startSid: $startSid, endSid: $endSid, detailContent: $detailContent, funFact: $funFact)';
}


}

/// @nodoc
abstract mixin class $LectureSegmentCopyWith<$Res>  {
  factory $LectureSegmentCopyWith(LectureSegment value, $Res Function(LectureSegment) _then) = _$LectureSegmentCopyWithImpl;
@useResult
$Res call({
 int idx, String title,@JsonKey(name: 'start_sid') String startSid,@JsonKey(name: 'end_sid') String endSid,@JsonKey(name: 'detail_content') String detailContent,@JsonKey(name: 'fun_fact') String? funFact
});




}
/// @nodoc
class _$LectureSegmentCopyWithImpl<$Res>
    implements $LectureSegmentCopyWith<$Res> {
  _$LectureSegmentCopyWithImpl(this._self, this._then);

  final LectureSegment _self;
  final $Res Function(LectureSegment) _then;

/// Create a copy of LectureSegment
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? idx = null,Object? title = null,Object? startSid = null,Object? endSid = null,Object? detailContent = null,Object? funFact = freezed,}) {
  return _then(_self.copyWith(
idx: null == idx ? _self.idx : idx // ignore: cast_nullable_to_non_nullable
as int,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,startSid: null == startSid ? _self.startSid : startSid // ignore: cast_nullable_to_non_nullable
as String,endSid: null == endSid ? _self.endSid : endSid // ignore: cast_nullable_to_non_nullable
as String,detailContent: null == detailContent ? _self.detailContent : detailContent // ignore: cast_nullable_to_non_nullable
as String,funFact: freezed == funFact ? _self.funFact : funFact // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [LectureSegment].
extension LectureSegmentPatterns on LectureSegment {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _LectureSegment value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _LectureSegment() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _LectureSegment value)  $default,){
final _that = this;
switch (_that) {
case _LectureSegment():
return $default(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _LectureSegment value)?  $default,){
final _that = this;
switch (_that) {
case _LectureSegment() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int idx,  String title, @JsonKey(name: 'start_sid')  String startSid, @JsonKey(name: 'end_sid')  String endSid, @JsonKey(name: 'detail_content')  String detailContent, @JsonKey(name: 'fun_fact')  String? funFact)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _LectureSegment() when $default != null:
return $default(_that.idx,_that.title,_that.startSid,_that.endSid,_that.detailContent,_that.funFact);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int idx,  String title, @JsonKey(name: 'start_sid')  String startSid, @JsonKey(name: 'end_sid')  String endSid, @JsonKey(name: 'detail_content')  String detailContent, @JsonKey(name: 'fun_fact')  String? funFact)  $default,) {final _that = this;
switch (_that) {
case _LectureSegment():
return $default(_that.idx,_that.title,_that.startSid,_that.endSid,_that.detailContent,_that.funFact);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int idx,  String title, @JsonKey(name: 'start_sid')  String startSid, @JsonKey(name: 'end_sid')  String endSid, @JsonKey(name: 'detail_content')  String detailContent, @JsonKey(name: 'fun_fact')  String? funFact)?  $default,) {final _that = this;
switch (_that) {
case _LectureSegment() when $default != null:
return $default(_that.idx,_that.title,_that.startSid,_that.endSid,_that.detailContent,_that.funFact);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _LectureSegment implements LectureSegment {
  const _LectureSegment({required this.idx, required this.title, @JsonKey(name: 'start_sid') required this.startSid, @JsonKey(name: 'end_sid') required this.endSid, @JsonKey(name: 'detail_content') required this.detailContent, @JsonKey(name: 'fun_fact') this.funFact});
  factory _LectureSegment.fromJson(Map<String, dynamic> json) => _$LectureSegmentFromJson(json);

@override final  int idx;
@override final  String title;
// JSONのキー名がCamelCaseじゃない場合、@JsonKeyで指定します
@override@JsonKey(name: 'start_sid') final  String startSid;
@override@JsonKey(name: 'end_sid') final  String endSid;
// Markdownの本文
@override@JsonKey(name: 'detail_content') final  String detailContent;
// 豆知識（無い場合も考慮して nullable にしておくと安全です）
@override@JsonKey(name: 'fun_fact') final  String? funFact;

/// Create a copy of LectureSegment
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LectureSegmentCopyWith<_LectureSegment> get copyWith => __$LectureSegmentCopyWithImpl<_LectureSegment>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$LectureSegmentToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _LectureSegment&&(identical(other.idx, idx) || other.idx == idx)&&(identical(other.title, title) || other.title == title)&&(identical(other.startSid, startSid) || other.startSid == startSid)&&(identical(other.endSid, endSid) || other.endSid == endSid)&&(identical(other.detailContent, detailContent) || other.detailContent == detailContent)&&(identical(other.funFact, funFact) || other.funFact == funFact));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,idx,title,startSid,endSid,detailContent,funFact);

@override
String toString() {
  return 'LectureSegment(idx: $idx, title: $title, startSid: $startSid, endSid: $endSid, detailContent: $detailContent, funFact: $funFact)';
}


}

/// @nodoc
abstract mixin class _$LectureSegmentCopyWith<$Res> implements $LectureSegmentCopyWith<$Res> {
  factory _$LectureSegmentCopyWith(_LectureSegment value, $Res Function(_LectureSegment) _then) = __$LectureSegmentCopyWithImpl;
@override @useResult
$Res call({
 int idx, String title,@JsonKey(name: 'start_sid') String startSid,@JsonKey(name: 'end_sid') String endSid,@JsonKey(name: 'detail_content') String detailContent,@JsonKey(name: 'fun_fact') String? funFact
});




}
/// @nodoc
class __$LectureSegmentCopyWithImpl<$Res>
    implements _$LectureSegmentCopyWith<$Res> {
  __$LectureSegmentCopyWithImpl(this._self, this._then);

  final _LectureSegment _self;
  final $Res Function(_LectureSegment) _then;

/// Create a copy of LectureSegment
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? idx = null,Object? title = null,Object? startSid = null,Object? endSid = null,Object? detailContent = null,Object? funFact = freezed,}) {
  return _then(_LectureSegment(
idx: null == idx ? _self.idx : idx // ignore: cast_nullable_to_non_nullable
as int,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,startSid: null == startSid ? _self.startSid : startSid // ignore: cast_nullable_to_non_nullable
as String,endSid: null == endSid ? _self.endSid : endSid // ignore: cast_nullable_to_non_nullable
as String,detailContent: null == detailContent ? _self.detailContent : detailContent // ignore: cast_nullable_to_non_nullable
as String,funFact: freezed == funFact ? _self.funFact : funFact // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}


/// @nodoc
mixin _$TranscriptSentence {

 String get sid; String get text;// JSONでは "start": 6720 となっているので int (ミリ秒) として扱います
 int get start; int get end;// "lecture", "qa", "chitchat" などの役割
 String get role;
/// Create a copy of TranscriptSentence
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TranscriptSentenceCopyWith<TranscriptSentence> get copyWith => _$TranscriptSentenceCopyWithImpl<TranscriptSentence>(this as TranscriptSentence, _$identity);

  /// Serializes this TranscriptSentence to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TranscriptSentence&&(identical(other.sid, sid) || other.sid == sid)&&(identical(other.text, text) || other.text == text)&&(identical(other.start, start) || other.start == start)&&(identical(other.end, end) || other.end == end)&&(identical(other.role, role) || other.role == role));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,sid,text,start,end,role);

@override
String toString() {
  return 'TranscriptSentence(sid: $sid, text: $text, start: $start, end: $end, role: $role)';
}


}

/// @nodoc
abstract mixin class $TranscriptSentenceCopyWith<$Res>  {
  factory $TranscriptSentenceCopyWith(TranscriptSentence value, $Res Function(TranscriptSentence) _then) = _$TranscriptSentenceCopyWithImpl;
@useResult
$Res call({
 String sid, String text, int start, int end, String role
});




}
/// @nodoc
class _$TranscriptSentenceCopyWithImpl<$Res>
    implements $TranscriptSentenceCopyWith<$Res> {
  _$TranscriptSentenceCopyWithImpl(this._self, this._then);

  final TranscriptSentence _self;
  final $Res Function(TranscriptSentence) _then;

/// Create a copy of TranscriptSentence
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? sid = null,Object? text = null,Object? start = null,Object? end = null,Object? role = null,}) {
  return _then(_self.copyWith(
sid: null == sid ? _self.sid : sid // ignore: cast_nullable_to_non_nullable
as String,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,start: null == start ? _self.start : start // ignore: cast_nullable_to_non_nullable
as int,end: null == end ? _self.end : end // ignore: cast_nullable_to_non_nullable
as int,role: null == role ? _self.role : role // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [TranscriptSentence].
extension TranscriptSentencePatterns on TranscriptSentence {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TranscriptSentence value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TranscriptSentence() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TranscriptSentence value)  $default,){
final _that = this;
switch (_that) {
case _TranscriptSentence():
return $default(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TranscriptSentence value)?  $default,){
final _that = this;
switch (_that) {
case _TranscriptSentence() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String sid,  String text,  int start,  int end,  String role)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TranscriptSentence() when $default != null:
return $default(_that.sid,_that.text,_that.start,_that.end,_that.role);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String sid,  String text,  int start,  int end,  String role)  $default,) {final _that = this;
switch (_that) {
case _TranscriptSentence():
return $default(_that.sid,_that.text,_that.start,_that.end,_that.role);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String sid,  String text,  int start,  int end,  String role)?  $default,) {final _that = this;
switch (_that) {
case _TranscriptSentence() when $default != null:
return $default(_that.sid,_that.text,_that.start,_that.end,_that.role);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _TranscriptSentence implements TranscriptSentence {
  const _TranscriptSentence({required this.sid, required this.text, required this.start, required this.end, required this.role});
  factory _TranscriptSentence.fromJson(Map<String, dynamic> json) => _$TranscriptSentenceFromJson(json);

@override final  String sid;
@override final  String text;
// JSONでは "start": 6720 となっているので int (ミリ秒) として扱います
@override final  int start;
@override final  int end;
// "lecture", "qa", "chitchat" などの役割
@override final  String role;

/// Create a copy of TranscriptSentence
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TranscriptSentenceCopyWith<_TranscriptSentence> get copyWith => __$TranscriptSentenceCopyWithImpl<_TranscriptSentence>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$TranscriptSentenceToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _TranscriptSentence&&(identical(other.sid, sid) || other.sid == sid)&&(identical(other.text, text) || other.text == text)&&(identical(other.start, start) || other.start == start)&&(identical(other.end, end) || other.end == end)&&(identical(other.role, role) || other.role == role));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,sid,text,start,end,role);

@override
String toString() {
  return 'TranscriptSentence(sid: $sid, text: $text, start: $start, end: $end, role: $role)';
}


}

/// @nodoc
abstract mixin class _$TranscriptSentenceCopyWith<$Res> implements $TranscriptSentenceCopyWith<$Res> {
  factory _$TranscriptSentenceCopyWith(_TranscriptSentence value, $Res Function(_TranscriptSentence) _then) = __$TranscriptSentenceCopyWithImpl;
@override @useResult
$Res call({
 String sid, String text, int start, int end, String role
});




}
/// @nodoc
class __$TranscriptSentenceCopyWithImpl<$Res>
    implements _$TranscriptSentenceCopyWith<$Res> {
  __$TranscriptSentenceCopyWithImpl(this._self, this._then);

  final _TranscriptSentence _self;
  final $Res Function(_TranscriptSentence) _then;

/// Create a copy of TranscriptSentence
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? sid = null,Object? text = null,Object? start = null,Object? end = null,Object? role = null,}) {
  return _then(_TranscriptSentence(
sid: null == sid ? _self.sid : sid // ignore: cast_nullable_to_non_nullable
as String,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,start: null == start ? _self.start : start // ignore: cast_nullable_to_non_nullable
as int,end: null == end ? _self.end : end // ignore: cast_nullable_to_non_nullable
as int,role: null == role ? _self.role : role // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
